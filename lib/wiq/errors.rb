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
  class APIError < Error
    attr_reader :status, :response_body, :request_id

    def initialize(status:, body:, request_id: nil)
      @status = status
      @response_body = body
      @request_id = request_id

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
        ["forbidden", "Server denied access (403): #{msgs}",
         "PATs inherit the user's permissions. Confirm the minting user can see this resource in the web app."]
      when 404
        ["not_found", "Resource not found (404).", nil]
      when 422
        ["validation_failed", "Validation error (422): #{msgs}", nil]
      when 429
        ["rate_limited", "Rate limited (429): #{msgs}",
         "WIQ enforces 100 req/3s per IP. Back off and retry."]
      else
        ["http_#{status}", "HTTP #{status}: #{msgs}", nil]
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
