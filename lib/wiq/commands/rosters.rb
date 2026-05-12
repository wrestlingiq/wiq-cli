# frozen_string_literal: true

module Wiq
  module Commands
    class Rosters < Base
      desc "list", "List rosters"
      method_option :season, type: :numeric,
                             desc: "Filter to rosters whose syncers point at paid sessions overlapping this year"
      method_option :season_tag, type: :string, desc: "Filter to rosters carrying this tag"
      method_option :archived, type: :boolean, desc: "Show only archived (true) or active (false)"
      method_option :all, type: :boolean, default: false
      def list
        params = { "per_page" => 100 }
        unless options[:archived].nil?
          params["q[archived_eq]"] = options[:archived]
        end

        records, total = fetch_index("/api/v1/rosters", params, key: "rosters")

        if options[:season]
          resolver = Wiq::SeasonResolver.new(client)
          ids = resolver.paid_session_ids_for(options[:season])
          raise Wiq::SeasonNotFoundError, options[:season] if ids.empty?

          records = resolver.filter_rosters_by_ids(records, ids)
        end

        if options[:season_tag]
          tag = options[:season_tag]
          records = records.select do |r|
            (r["taggings"] || []).any? { |t| t.dig("tag", "name") == tag }
          end
        end

        render_index(records, total: total,
                              summary: "Listed #{records.size} rosters.")
      end

      desc "show ID", "Fetch a single roster"
      def show(id)
        roster = client.get("/api/v1/rosters/#{id}")
        render(roster, summary: "Roster #{roster["id"]} — #{roster["name"]}")
      end
    end
  end
end
