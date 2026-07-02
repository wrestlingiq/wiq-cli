# frozen_string_literal: true

module Wiq
  module Commands
    class Rosters < Base
      desc "list", "List rosters"
      long_desc <<~DESC
        Returns every roster on the calling profile's team, paginated.

        Season filtering is a CLI-side projection (WIQ has no first-class
        Season entity):
          --season <year>       Resolves to paid_session ids whose date
                                window overlaps that calendar year, then
                                filters rosters whose roster_syncers point
                                at any of those paid sessions.
          --season-tag <tag>    Filters rosters carrying a tag with that
                                exact name. Some teams tag rosters with
                                conventions like "2025-26".

        --location <id> filters server-side (Ransack q[location_id_eq]) to
        rosters stamped with that structured location. Discover ids via
        `wiq locations list`. Rosters with no location are excluded when
        the filter is on. Each roster row embeds its location object (or
        null) so you can also group client-side without the filter.

        Each roster row embeds roster_syncers and taggings, which is what
        --season uses to filter without needing extra calls.
      DESC
      method_option :season, type: :numeric,
                             desc: "Filter to rosters whose syncers point at paid sessions overlapping this year"
      method_option :season_tag, type: :string, desc: "Filter to rosters carrying this tag"
      method_option :location, type: :numeric, desc: "Filter to rosters at one location id"
      method_option :archived, type: :boolean, desc: "Show only archived (true) or active (false)"
      method_option :all, type: :boolean, default: false
      def list
        params = { "per_page" => 100 }
        unless options[:archived].nil?
          params["q[archived_eq]"] = options[:archived]
        end
        params["q[location_id_eq]"] = options[:location] if options[:location]

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

        render_index(
          records, total: total,
          summary: "Listed #{records.size} rosters.",
          breadcrumbs: [
            { "cmd" => "wiq rosters show <id>", "description" => "Inspect a single roster" },
            { "cmd" => "wiq reports run RosterReport --roster <id>",
              "description" => "Export the roster as a report" }
          ]
        )
      end

      desc "show ID", "Fetch a single roster"
      long_desc <<~DESC
        Full roster payload: name, archived flag, age_division_id, taggings
        (with tag metadata), roster_syncers (linkage to paid sessions), and
        an embedded stats.roster_memberships_count.
      DESC
      def show(id)
        roster = client.get("/api/v1/rosters/#{id}")
        render(roster,
               summary: "Roster #{roster["id"]} — #{roster["name"]}",
               breadcrumbs: [
                 { "cmd" => "wiq reports run RosterStatsReport --roster #{roster["id"]} --start <date> --end <date>",
                   "description" => "Pull stats for this roster" },
                 { "cmd" => "wiq check_ins summary --roster #{roster["id"]} --start <date> --end <date>",
                   "description" => "Attendance summary for this roster" }
               ])
      end
    end
  end
end
