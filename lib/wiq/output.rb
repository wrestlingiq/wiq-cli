# frozen_string_literal: true

require "json"

module Wiq
  # Three output modes:
  #   --json   full envelope (ok/data/summary/meta) for agents that want structure
  #   --agent  bare JSON of `data` for headless scripts
  #   default  pretty JSON to a TTY, or --agent equivalent when piped
  module Output
    module_function

    def render(data, summary: nil, breadcrumbs: [], meta: {}, options: {})
      mode = pick_mode(options)
      case mode
      when :json
        puts JSON.pretty_generate(envelope(data, summary: summary, breadcrumbs: breadcrumbs, meta: meta))
      when :agent
        puts JSON.generate(data)
      when :pretty
        puts JSON.pretty_generate(data)
        puts "" unless data.nil? || (data.respond_to?(:empty?) && data.empty?)
        puts "→ #{summary}" if summary
        if meta && !meta.empty?
          meta_line = meta.map { |k, v| "#{k}=#{v}" }.join("  ")
          puts "  #{meta_line}"
        end
      end
    end

    def render_error(err, options: {})
      mode = pick_mode(options)
      payload = {
        "ok" => false,
        "error" => err.message,
        "code" => err.respond_to?(:code) ? err.code : "error",
        "hint" => (err.respond_to?(:hint) ? err.hint : nil),
        "details" => (err.respond_to?(:details) ? err.details : nil)
      }.compact

      case mode
      when :json, :agent
        warn JSON.generate(payload)
      else
        warn "✖ #{payload["error"]} [#{payload["code"]}]"
        warn "  hint: #{payload["hint"]}" if payload["hint"]
      end
    end

    def pick_mode(options)
      options ||= {}
      return :agent if options[:agent] || options["agent"]
      return :json  if options[:json]  || options["json"]
      $stdout.tty? ? :pretty : :agent
    end

    def envelope(data, summary:, breadcrumbs:, meta:)
      {
        "ok" => true,
        "data" => data,
        "summary" => summary,
        "breadcrumbs" => breadcrumbs,
        "meta" => meta
      }.compact
    end
  end
end
