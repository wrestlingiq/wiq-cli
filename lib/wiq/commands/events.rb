# frozen_string_literal: true

module Wiq
  module Commands
    class Events < Base
      desc "list", "List events in a date range"
      method_option :start, type: :string, required: true, desc: "YYYY-MM-DD (team timezone)"
      method_option :end, type: :string, required: true, desc: "YYYY-MM-DD (team timezone)"
      method_option :roster, type: :array, desc: "One or more roster ids"
      method_option :event_type, type: :string, desc: "e.g. practice, competition, dual_meet"
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

        records, total = fetch_index("/api/v1/events", params, key: "events")
        render_index(records, total: total,
                              summary: "Listed #{records.size} events #{options[:start]}..#{options[:end]}.")
      end

      desc "show ID", "Fetch a single event"
      method_option :expand, type: :string,
                             desc: "CSV: event_invites, event_bookings, private_lessons"
      def show(id)
        params = {}
        params["expand"] = options[:expand] if options[:expand]
        event = client.get("/api/v1/events/#{id}", params)
        render(event, summary: "Event #{event["id"]} — #{event["name"]}")
      end
    end
  end
end
