# frozen_string_literal: true

module Wiq
  class Error < StandardError
    attr_reader :code, :hint, :exit_code, :details

    def initialize(message, code: "error", hint: nil, exit_code: 1, details: nil)
      super(message)
      @code = code
      @hint = hint
      @exit_code = exit_code
      @details = details
    end
  end

  class ConfigError < Error
    def initialize(message, code: "config_error", **opts)
      super(message, code: code, **opts)
    end
  end

  class HostUnsetError < ConfigError
    def initialize
      super(
        "No WIQ host configured.",
        code: "host_unset",
        hint: "Run `wiq auth login` to configure a host and token, or pass --host."
      )
    end
  end

  class NotAuthenticatedError < ConfigError
    def initialize
      super(
        "No personal access token configured.",
        code: "not_authenticated",
        hint: "Run `wiq auth login` to store a PAT for this host."
      )
    end
  end

  class AmbiguousAliasError < ConfigError
    def initialize(host, aliases)
      super(
        "Multiple credential aliases stored for #{host}: #{aliases.join(", ")}.",
        code: "ambiguous_alias",
        hint: "Pass --as <alias>, set WIQ_ALIAS, or add `alias` to .wiq/config.json. " \
              "Run `wiq auth list` to see what's stored."
      )
    end
  end

  class AliasNotFoundError < ConfigError
    def initialize(host, alias_name, available)
      hint = if available.empty?
        "No credentials stored for this host. Run `wiq auth login`."
      else
        "Available aliases for #{host}: #{available.join(", ")}."
      end
      super(
        "No credential stored for #{host} under alias #{alias_name.inspect}.",
        code: "alias_not_found",
        hint: hint
      )
    end
  end

  class AliasConflictError < ConfigError
    def initialize(host, alias_name)
      super(
        "An entry already exists for #{host} under alias #{alias_name.inspect}.",
        code: "alias_conflict",
        hint: "Pass --as <other-name> to store under a different slot, or --force to overwrite."
      )
    end
  end

  # Mirror of the HTTP error envelope from /api/v1.
  #
  # PAT write policy (Api::V1::BaseController#enforce_pat_restrictions):
  # a write goes through only when it maps to a capability in the server's
  # ApiCapability registry that the team has enabled AND the token carries.
  # The server emits three distinct 403 bodies for the three failure modes,
  # naming the capability verbatim; we key off that wording to give each
  # its own `code` + fix-it hint. Keep the regexes in sync with
  # `pat_denial_message` in the Rails app.
  class APIError < Error
    attr_reader :status, :response_body, :request_id, :capability

    PAT_NOT_WRITABLE = /not writable with a personal access token/i
    PAT_TEAM_DISABLED = /team has not enabled (\S+) for API access/i
    PAT_TOKEN_MISSING_SCOPE = /token lacks the (\S+) scope/i
    PAT_LEGACY_READ_ONLY = /personal access tokens are read-only/i
    PAT_STAGE_REFUSED = /stage cannot move from (\S+) to (\S+) with a personal access token/i

    def initialize(status:, body:, request_id: nil)
      @status = status
      @response_body = body
      @request_id = request_id
      @capability = nil

      code, message, hint = derive(status, body)
      super(message, code: code, hint: hint, exit_code: 1, details: body)
    end

    private

    def derive(status, body)
      msgs = extract_messages(body)
      case status
      when 401
        ["unauthorized", "Token rejected by server (401).",
         "Run `wiq auth status` to inspect the active token; `wiq auth login` to replace it."]
      when 403
        derive_forbidden(msgs)
      when 404
        ["not_found", "Resource not found (404).", nil]
      when 422
        derive_unprocessable(msgs)
      when 429
        ["rate_limited", "Rate limited (429): #{msgs}",
         "WIQ enforces 100 req/3s per IP. Back off and retry."]
      else
        ["http_#{status}", "HTTP #{status}: #{msgs}", nil]
      end
    end

    def derive_forbidden(msgs)
      if msgs =~ PAT_NOT_WRITABLE || msgs =~ PAT_LEGACY_READ_ONLY
        ["pat_write_unsupported", "Server denied access (403): #{msgs}",
         "This endpoint has no API write capability, so no personal access token can call it. " \
         "Make the change in the WIQ web app."]
      elsif (m = msgs.match(PAT_TEAM_DISABLED))
        @capability = m[1]
        ["capability_disabled_for_team", "Server denied access (403): #{msgs}",
         "A team admin must enable #{@capability} under Settings → API Access " \
         "(<host>/settings/team/api_access). Existing tokens minted with that scope start working immediately."]
      elsif (m = msgs.match(PAT_TOKEN_MISSING_SCOPE))
        @capability = m[1]
        ["token_missing_scope", "Server denied access (403): #{msgs}",
         "Token scopes are immutable. Mint a new token that includes #{@capability} at " \
         "<host>/settings/personal_access_tokens, then `wiq auth login --force` to replace the stored one. " \
         "Run `wiq auth status` to see the scopes on the current token."]
      else
        ["forbidden", "Server denied access (403): #{msgs}",
         "PATs inherit the user's permissions. Confirm the minting user can see this resource in the web app."]
      end
    end

    def derive_unprocessable(msgs)
      if msgs =~ PAT_STAGE_REFUSED
        ["stage_transition_refused", "Validation error (422): #{msgs}",
         "Stage changes via a personal access token are forward-only and cannot leave a terminal stage " \
         "(converted, didnt_join, archived). A coach can force the move in the WIQ web app."]
      else
        ["validation_failed", "Validation error (422): #{msgs}", nil]
      end
    end

    # /api/v1 always returns { "errors": <array|hash> }. Flatten to a human string.
    def extract_messages(body)
      return body.to_s unless body.is_a?(Hash)

      errs = body["errors"] || body[:errors]
      return "no error body" if errs.nil?

      case errs
      when Array
        errs.join("; ")
      when Hash
        errs.flat_map { |field, msgs| Array(msgs).map { |m| "#{field}: #{m}" } }.join("; ")
      else
        errs.to_s
      end
    end
  end

  class ReportFailedError < Error
    def initialize(report)
      super(
        "Report ##{report["id"]} (#{report["type"]}) finished with status `failed`.",
        code: "report_failed",
        details: report["result"]
      )
    end
  end

  class ReportTimeoutError < Error
    def initialize(report, timeout)
      super(
        "Report ##{report["id"]} did not finish within #{timeout}s (last status: #{report["status"]}).",
        code: "report_timeout",
        hint: "Pass --timeout to wait longer, or re-check later with `wiq reports show #{report["id"]}`.",
        details: report
      )
    end
  end

  class SeasonNotFoundError < Error
    def initialize(year)
      super(
        "No paid sessions overlap year #{year}.",
        code: "season_not_found",
        hint: "Run `wiq paid_sessions list` to see configured registration periods."
      )
    end
  end

  class SeasonUnsupportedError < Error
    def initialize(type, matches)
      super(
        "Season #{matches.size > 1 ? "is ambiguous" : "cannot be applied automatically"} for report type #{type}.",
        code: "season_unsupported_for_type",
        hint: "Pass --paid-session <id> explicitly. Matching paid sessions: #{matches.map { |m| m["id"] }.join(", ")}"
      )
    end
  end
end
