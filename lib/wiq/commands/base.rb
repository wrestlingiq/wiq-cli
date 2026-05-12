# frozen_string_literal: true

require "thor"

module Wiq
  module Commands
    # Parent class for every subcommand group. Defines the cross-cutting
    # --host / --json / --agent options and the helpers each command uses.
    class Base < Thor
      class_option :host, type: :string,
                          desc: "WIQ host URL (overrides env + config + credential store)"
      class_option :as, type: :string,
                        desc: "Credential alias to use (overrides env + config + sole/default)"
      class_option :json, type: :boolean, default: false,
                          desc: "Output the full JSON envelope"
      class_option :agent, type: :boolean, default: false,
                           desc: "Output bare JSON of `data` with no envelope or colors"

      def self.exit_on_failure?
        true
      end

      no_commands do
        def config
          @config ||= Wiq::Config.load(symbolized_options)
        end

        def client
          @client ||= begin
            config.require_token!
            Wiq::Client.new(config)
          end
        end

        def symbolized_options
          @symbolized_options ||= options.each_with_object({}) { |(k, v), h| h[k.to_sym] = v }
        end

        def render(data, summary: nil, breadcrumbs: [], meta: {})
          Wiq::Output.render(data, summary: summary, breadcrumbs: breadcrumbs,
                                   meta: meta.merge("host" => config.host).compact,
                                   options: symbolized_options)
        end

        def render_index(records, total: nil, page: nil, summary: nil, breadcrumbs: [])
          meta = { "count" => records.size }
          meta["total"] = total if total
          meta["page"] = page if page
          render(records, summary: summary, breadcrumbs: breadcrumbs, meta: meta)
        end

        def fetch_index(path, params, key:)
          if options[:all]
            records, total = client.collect_all(path, params, key: key)
            [records, total, nil]
          else
            records = []
            total = nil
            client.paginate(path, params, key: key) do |page_records, _resp, t|
              records = page_records
              total = t
              break
            end
            [records, total, nil]
          end
        end
      end
    end
  end
end
