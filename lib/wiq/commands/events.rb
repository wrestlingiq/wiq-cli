# frozen_string_literal: true

module Wiq
  module Commands
    class Events < Base
      # Canonical event_type strings from app/models/event.rb. Surfaced via
      # `wiq events types` so agents don't have to guess.
      TYPES = {
        "practice" => "Practice events. The default for most clubs.",
        "dual_meet" => "Dual meet — match-style competition against one opposing team.",
        "tournament" => "Tournament — bracket-style competition with many opponents.",
        "scramble" => "Scramble — open mat / informal competition.",
        "private_lesson" => "Private lesson — one-on-one or small-group paid session. " \
                            "Filtered out of the default `events list` unless you opt in.",
        "other" => "Miscellaneous events that don't fit the other types."
      }.freeze

      desc "list", "List events in a date range"
      long_desc <<~DESC
        Fetches events between --start and --end (inclusive). Dates are parsed
        in the team's default timezone server-side, so pass plain YYYY-MM-DD —
        the CLI does not need timezone awareness.

        Filters apply server-side:
          --event-type     One of `wiq events types` (practice, dual_meet, ...)
          --roster         One or more roster ids (the API joins through
                           roster_events)
          --location       One or more location ids (structured Location
                           records; discover via `wiq locations list`)
          --expand         CSV of event_invites,event_bookings,private_lessons.
                           Drops nested data into each event row.

        Location caveat: --location matches the event's own structured
        location_id. Events with NO location set are excluded from a
        filtered listing — they only appear when you don't filter. The
        legacy free-text `location` field still exists on old events; the
        serialized `location` value is the display form (structured record
        when set, else the free text).

        Use --all to walk every page; default is page 1, per_page=100.
      DESC
      method_option :start, type: :string, required: true, desc: "YYYY-MM-DD (team timezone)"
      method_option :end, type: :string, required: true, desc: "YYYY-MM-DD (team timezone)"
      method_option :roster, type: :array, desc: "One or more roster ids"
      method_option :location, type: :array,
                               desc: "One or more location ids (events with no location are excluded)"
      method_option :event_type, type: :string, enum: %w[practice dual_meet tournament scramble private_lesson other],
                                 desc: "Filter to one event_type (see `wiq events types`)"
      method_option :expand, type: :string,
                             desc: "CSV: event_invites, event_bookings, private_lessons"
      method_option :all, type: :boolean, default: false
      def list
        params = {
          "start" => options[:start],
          "end" => options[:end],
          "per_page" => 100
        }
        params["event_type"] = options[:event_type] if options[:event_type]
        params["expand"] = options[:expand] if options[:expand]
        if options[:roster]
          options[:roster].each { |rid| (params["roster_ids[]"] ||= []) << rid }
        end
        if options[:location]
          options[:location].each { |lid| (params["location_ids[]"] ||= []) << lid }
        end

        records, total = fetch_index("/api/v1/events", params, key: "events")
        render_index(
          records, total: total,
          summary: "Listed #{records.size} events #{options[:start]}..#{options[:end]}.",
          breadcrumbs: [
            { "cmd" => "wiq events show <id>", "description" => "Inspect a single event" },
            { "cmd" => "wiq check_ins event <id>", "description" => "See check-ins for an event" }
          ]
        )
      end

      desc "show ID", "Fetch a single event"
      long_desc <<~DESC
        Single-event drill-down. The base payload covers all the obvious
        fields (name, type, start/end, location, color, roster_events,
        team_scores, paid_session).

        Pass --expand to inline related collections:
          event_invites      Per-invitee RSVP status
          event_bookings     Per-bookee status (private lessons, paid drop-ins)
          private_lessons    Linked private lessons + nested bookings

        Soft-deleted events are not returned.
      DESC
      method_option :expand, type: :string,
                             desc: "CSV: event_invites, event_bookings, private_lessons"
      def show(id)
        params = {}
        params["expand"] = options[:expand] if options[:expand]
        event = client.get("/api/v1/events/#{id}", params)
        render(event,
               summary: "Event #{event["id"]} — #{event["name"]}",
               breadcrumbs: [
                 { "cmd" => "wiq check_ins event #{event["id"]}", "description" => "See check-ins" },
                 { "cmd" => "wiq reports run EventStatsReport --event #{event["id"]}",
                   "description" => "Run per-event stats" }
               ])
      end

      desc "types", "Print the canonical event_type strings"
      long_desc <<~DESC
        Static enum sourced from app/models/event.rb. Use these values with
        --event-type on `wiq events list`. Note that the API will accept
        any string in the event_type column, but values outside this list
        won't filter anything useful.
      DESC
      def types
        rows = TYPES.map { |type, desc| { "event_type" => type, "description" => desc } }
        render_index(rows, summary: "Canonical event_type values.")
      end
    end
  end
end
