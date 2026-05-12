# frozen_string_literal: true

module Wiq
  module Commands
    class Doctor < Base
      desc "check", "Diagnose env, network, token, and config sources"
      def check_all
        checks = []

        checks << check("Ruby version", RUBY_VERSION,
                        ok: Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.1.0"),
                        hint: "wiq-cli requires Ruby >= 3.1")

        cfg = Wiq::Config.load(symbolized_options)
        trace = cfg.trace
        checks << check("Credentials path", Wiq::Credentials.path, ok: true)

        checks << check("Host", trace[:host] || "(unset)",
                        ok: !trace[:host].nil?,
                        hint: trace[:host_source] || "Run `wiq auth login` to configure.")

        checks << check("Alias", trace[:alias] || "(unresolved)",
                        ok: !trace[:alias].nil?,
                        hint: trace[:alias_source])

        checks << check("Token", trace[:token_present] ? "present" : "missing",
                        ok: trace[:token_present],
                        hint: trace[:token_source])

        if trace[:host] && trace[:token_present]
          begin
            client = Wiq::Client.new(cfg)
            rows, = client.collect_all(
              "/api/v1/personal_access_tokens",
              { "per_page" => 100 },
              key: "personal_access_tokens"
            )
            prefix = cfg.token[0, 12]
            match = rows.find { |r| r["token_prefix"] == prefix }
            if match
              profile = match["profile"] || {}
              checks << check("Reachability + auth", "200 OK", ok: true)
              checks << check("Bound profile",
                              "#{profile["display_name"]} (#{profile["type"]}) @ #{profile["team_name"]}",
                              ok: !profile["display_name"].nil?)
            else
              checks << check("Reachability + auth", "200 OK", ok: true)
              checks << check("Bound profile", "(token not in own user's PAT list?)",
                              ok: false,
                              hint: "Unexpected — the calling PAT should always appear in this list.")
            end
          rescue Wiq::APIError => e
            checks << check("Reachability + auth", "#{e.status} #{e.code}", ok: false, hint: e.hint)
          rescue Faraday::Error => e
            checks << check("Reachability + auth", e.message, ok: false,
                            hint: "Check the host URL and your network.")
          end
        else
          checks << check("Reachability + auth", "skipped", ok: false, hint: "Host or token missing.")
        end

        all_ok = checks.all? { |c| c["ok"] }
        render(checks, summary: all_ok ? "All checks passed." : "Some checks failed.")
        exit(1) unless all_ok
      end

      map "check" => :check_all
      default_task :check_all

      no_commands do
        def check(name, value, ok:, hint: nil)
          { "name" => name, "value" => value, "ok" => ok, "hint" => hint }.compact
        end
      end
    end
  end
end
