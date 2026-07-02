# frozen_string_literal: true

module Wiq
  module Commands
    class Locations < Base
      desc "list", "List the team's structured locations (sites/gyms)"
      long_desc <<~DESC
        Locations are WIQ's structured multi-site concept — a named place
        (with optional street address) that rosters, events, paid sessions,
        wrestlers, metrics, and reports can be scoped to. Single-site clubs
        typically have zero or one; multi-site clubs use them to slice
        everything per gym.

        Archived locations are hidden by default; pass --include-archived
        to see them. Ordered by name server-side.

        This is the ID-discovery surface for every --location flag in the
        CLI:
          wiq rosters list --location <id>
          wiq events list --location <id> [...more ids]
          wiq wrestlers list --location <id>
          wiq paid_sessions list --location <id>
          wiq metrics show <name> --location <id>
          wiq reports run <Type> --location <id>
      DESC
      method_option :include_archived, type: :boolean, default: false,
                                       desc: "Include archived locations"
      method_option :all, type: :boolean, default: false
      def list
        params = { "per_page" => 100 }
        params["include_archived"] = true if options[:include_archived]

        records, total = fetch_index("/api/v1/locations", params, key: "locations")
        render_index(
          records, total: total,
          summary: "Listed #{records.size} locations#{options[:include_archived] ? " (including archived)" : ""}.",
          breadcrumbs: [
            { "cmd" => "wiq locations show <id>", "description" => "Inspect a single location" },
            { "cmd" => "wiq rosters list --location <id>", "description" => "Rosters at a location" },
            { "cmd" => "wiq metrics show mrr --location <id>",
              "description" => "Finance metrics scoped to a location (admin only)" }
          ]
        )
      end

      desc "show ID", "Fetch a single location"
      long_desc <<~DESC
        Full location payload: id, name, address_line1, address_line2,
        city, state, postal_code, country, archived.
      DESC
      def show(id)
        location = client.get("/api/v1/locations/#{id}")
        render(location,
               summary: "Location #{location["id"]} — #{location["name"]}",
               breadcrumbs: [
                 { "cmd" => "wiq rosters list --location #{location["id"]}",
                   "description" => "Rosters at this location" },
                 { "cmd" => "wiq wrestlers list --location #{location["id"]}",
                   "description" => "Wrestlers on any roster at this location" }
               ])
      end
    end
  end
end
