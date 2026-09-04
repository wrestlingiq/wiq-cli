# frozen_string_literal: true

require "io/console"

module Wiq
  module Commands
    class Auth < Base
      desc "login", "Store a personal access token for a WIQ host"
      long_desc <<~DESC
        Stores a PAT in ~/.config/wiq/credentials.json (mode 0600) keyed by
        host + alias.

        First-time login slots into "default" automatically. If "default" is
        already taken, pass --as <alias> to create a separate slot — this is
        how the CLI supports multiple WIQ accounts (different clubs, different
        roles) on the same host.

        Customers mint PATs at <host>/settings/personal_access_tokens. The
        plaintext is shown once at creation; paste it into this command (or
        use --token).

        Verification: the CLI hits `GET /api/v1/personal_access_tokens` to
        confirm the token works AND fetch the bound profile (display_name,
        team_name, type) plus the token's write `scopes` in one round trip.
        That metadata is shown after login and stored alongside the token.

        Scopes: every PAT can read. Writes need a capability (currently
        prospects:write, reports:write) that the team admin has enabled
        under Settings → API Access AND that the token was minted with.
        Scopes are immutable — to change them, revoke and mint a new
        token, then re-run this command with --force.
      DESC
      method_option :token, type: :string, desc: "PAT value (otherwise prompted interactively)"
      method_option :force, type: :boolean, default: false,
                            desc: "Overwrite an existing entry at this host+alias slot"
      def login
        default_host = Wiq::Config::PRODUCTION_HOST
        host = options[:host] || prompt("WIQ host URL [#{default_host}]: ")
        host = host.to_s.strip
        host = default_host if host.empty?
        unless host.start_with?("http")
          raise Wiq::ConfigError.new("Host must be an absolute URL, got #{host.inspect}.",
                                     code: "invalid_host")
        end

        token = options[:token] || prompt_secret("Personal access token: ")
        token = token.to_s.strip
        unless token.start_with?("wiq_pat_")
          raise Wiq::ConfigError.new("Token does not start with `wiq_pat_`.",
                                     code: "invalid_token",
                                     hint: "Mint a PAT at <host>/settings/personal_access_tokens.")
        end

        alias_name = pick_login_alias(host, options[:as])

        if Wiq::Credentials.for_host(host, alias_name) && !options[:force]
          raise Wiq::AliasConflictError.new(host, alias_name)
        end

        cfg = Wiq::Config.new
        cfg.instance_variable_set(:@host, host)
        cfg.instance_variable_set(:@token, token)
        client = Wiq::Client.new(cfg)

        metadata = lookup_token_metadata(client, token)

        Wiq::Credentials.store(
          host: host,
          alias_name: alias_name,
          token: token,
          token_prefix: metadata[:token_prefix],
          name: metadata[:name],
          profile: metadata[:profile],
          scopes: metadata[:scopes]
        )

        render(
          {
            "host" => host,
            "alias" => alias_name,
            "token_prefix" => metadata[:token_prefix],
            "name" => metadata[:name],
            "profile" => metadata[:profile],
            "scopes" => metadata[:scopes],
            "stored_at" => Wiq::Credentials.for_host(host, alias_name)["stored_at"]
          }.compact,
          summary: profile_summary("Stored PAT for #{host} as #{alias_name.inspect}",
                                   metadata[:profile], metadata[:scopes]),
          breadcrumbs: [
            { "cmd" => "wiq auth status --as #{alias_name}",
              "description" => "Verify the stored token works" },
            { "cmd" => "wiq auth list", "description" => "See all stored credentials" }
          ]
        )
      end

      desc "status", "Show the configured host, alias, and bound profile"
      long_desc <<~DESC
        Resolves the configuration chain (--host/--as flags → env vars →
        .wiq/config.json → credentials store) and reports which source won.

        Performs a best-effort live probe against
        `/api/v1/personal_access_tokens` to confirm the token still works
        and surface the live last_used_at and write `scopes` (empty =
        read-only). Check `live_scopes` before attempting a write command
        such as `wiq prospects advance`. If the probe fails (network,
        revoked token, host unreachable), the error appears in `live_error`
        rather than aborting the command — local state is always shown.

        Useful as the first call when an agent inherits a configured shell:
        verifies host, alias, profile binding, and team in one shot.
      DESC
      def status
        cfg = Wiq::Config.load(symbolized_options)
        raise Wiq::HostUnsetError unless cfg.host

        store_entry = cfg.alias_name ? Wiq::Credentials.for_host(cfg.host, cfg.alias_name) || {} : {}
        live_metadata = nil
        live_error = nil
        if cfg.token
          begin
            client = Wiq::Client.new(cfg)
            live_metadata = lookup_token_metadata(client, cfg.token)
          rescue Wiq::APIError, Faraday::Error => e
            live_error = e.message
          end
        end

        data = {
          "host" => cfg.host,
          "host_source" => cfg.sources[:host],
          "alias" => cfg.alias_name,
          "alias_source" => cfg.sources[:alias],
          "token_present" => !cfg.token.nil?,
          "token_source" => cfg.sources[:token],
          "token_prefix" => store_entry["token_prefix"],
          "stored_name" => store_entry["name"],
          "stored_profile" => store_entry["profile"],
          "stored_scopes" => store_entry["scopes"],
          "live_name" => live_metadata&.dig(:name),
          "live_last_used_at" => live_metadata&.dig(:last_used_at),
          "live_profile" => live_metadata&.dig(:profile),
          "live_scopes" => live_metadata&.dig(:scopes),
          "live_error" => live_error
        }.compact

        summary =
          if !cfg.token
            cfg.alias_name ? "No token stored for alias #{cfg.alias_name.inspect}." \
                          : "No alias resolvable for this host."
          else
            profile_summary("Token reachable (alias=#{cfg.alias_name})",
                            live_metadata&.dig(:profile) || store_entry["profile"],
                            live_metadata ? live_metadata[:scopes] : store_entry["scopes"])
          end

        render(data, summary: summary)
      end

      desc "logout", "Remove a stored credential slot"
      long_desc <<~DESC
        Removes a single stored credential by host + alias. The PAT is NOT
        revoked server-side — to revoke, use the web UI at
        <host>/settings/personal_access_tokens. Logout just clears the
        local file entry.
      DESC
      def logout
        cfg = Wiq::Config.load(symbolized_options)
        raise Wiq::HostUnsetError unless cfg.host
        unless cfg.alias_name
          aliases = Wiq::Credentials.aliases_for(cfg.host)
          raise Wiq::AmbiguousAliasError.new(cfg.host, aliases) unless aliases.empty?

          render({ "host" => cfg.host, "removed" => false },
                 summary: "No credentials stored for #{cfg.host}.")
          return
        end

        removed = Wiq::Credentials.remove(cfg.host, cfg.alias_name)
        render(
          { "host" => cfg.host, "alias" => cfg.alias_name, "removed" => removed },
          summary: removed ? "Cleared #{cfg.alias_name.inspect} for #{cfg.host}." \
                          : "No credential stored at #{cfg.host} / #{cfg.alias_name.inspect}."
        )
      end

      desc "list", "List all stored credentials across hosts and aliases"
      long_desc <<~DESC
        Dumps every stored credential across all hosts and aliases. Never
        includes the raw token (only token_prefix); safe to share or log.

        Useful for agents inheriting a shared shell — they can see what's
        available before invoking commands.
      DESC
      def list
        entries = Wiq::Credentials.all_entries
        render_index(
          entries,
          summary: "Stored credentials: #{entries.size}.",
          breadcrumbs: [
            { "cmd" => "wiq auth status --as <alias>", "description" => "Inspect a specific slot" }
          ]
        )
      end

      no_commands do
        def prompt(label)
          $stderr.print(label)
          $stdin.gets.to_s.chomp
        end

        def prompt_secret(label)
          $stderr.print(label)
          val = $stdin.noecho(&:gets).to_s.chomp
          $stderr.puts ""
          val
        rescue Errno::ENOTTY, IOError
          $stdin.gets.to_s.chomp
        end

        # Decide which slot to write to. Explicit --as wins. Otherwise:
        # - empty bucket → "default"
        # - "default" free → "default"
        # - "default" taken → demand --as
        def pick_login_alias(host, requested)
          return requested if requested && !requested.empty?

          existing = Wiq::Credentials.aliases_for(host)
          return Wiq::Credentials::DEFAULT_ALIAS if existing.empty?
          return Wiq::Credentials::DEFAULT_ALIAS unless existing.include?(Wiq::Credentials::DEFAULT_ALIAS)

          raise Wiq::ConfigError.new(
            "An entry already exists at #{host} under alias \"default\".",
            code: "alias_required",
            hint: "Pass --as <name> to store under a different slot, or --force to overwrite default."
          )
        end

        def lookup_token_metadata(client, token)
          prefix = token[0, 12]
          rows, = client.collect_all(
            "/api/v1/personal_access_tokens",
            { "per_page" => 100 },
            key: "personal_access_tokens"
          )
          match = rows.find { |r| r["token_prefix"] == prefix }
          return { token_prefix: prefix, name: nil, last_used_at: nil, profile: nil, scopes: nil } unless match

          {
            token_prefix: match["token_prefix"],
            name: match["name"],
            last_used_at: match["last_used_at"],
            profile: match["profile"],
            # Servers predating per-token scopes omit the key; treat as read-only.
            scopes: Array(match["scopes"])
          }
        end

        def profile_summary(prefix, profile, scopes = nil)
          scope_note =
            if scopes.nil?
              nil
            elsif scopes.empty?
              "scopes: read-only"
            else
              "scopes: #{scopes.join(", ")}"
            end
          return [prefix, scope_note].compact.join("; ") + "." unless profile

          who = profile["display_name"]
          where = profile["team_name"]
          kind = profile["type"]
          tail = [who, where].compact.reject(&:empty?).join(" @ ")
          tail += " (#{kind})" if kind && !kind.empty?
          head = tail.empty? ? prefix : "#{prefix} — #{tail}"
          [head, scope_note].compact.join("; ") + "."
        end
      end
    end
  end
end
