# frozen_string_literal: true

module Wiq
  module Commands
    class CheckIns < Base
      desc "event EVENT_ID", "List check-ins for an event"
      method_option :status, type: :string, desc: "Filter by status (Ransack q[status_eq])"
      method_option :all, type: :boolean, default: false, desc: "Follow pagination until exhausted"
      def event(event_id)
        params = { "per_page" => 50 }
        params["q[status_eq]"] = options[:status] if options[:status]
        records, total = fetch_index("/api/v1/events/#{event_id}/check_ins", params, key: "check_ins")
        render_index(records, total: total,
                              summary: "Listed #{records.size} check-ins for event #{event_id}.")
      end

      desc "wrestler WRESTLER_ID", "List a wrestler's check-ins"
      method_option :since, type: :string, desc: "Earliest created_at date (YYYY-MM-DD)"
      method_option :all, type: :boolean, default: false
      def wrestler(wrestler_id)
        params = { "per_page" => 50 }
        params["q[created_at_gteq]"] = options[:since] if options[:since]
        records, total = fetch_index("/api/v1/wrestlers/#{wrestler_id}/check_ins", params, key: "check_ins")
        render_index(records, total: total,
                              summary: "Listed #{records.size} check-ins for wrestler #{wrestler_id}.")
      end

      desc "summary", "Run a CheckInSummaryReport (default) or CheckInFeedReport for a date range"
      method_option :start, type: :string, required: true, desc: "YYYY-MM-DD"
      method_option :end, type: :string, required: true, desc: "YYYY-MM-DD"
      method_option :roster, type: :numeric, desc: "Restrict to a single roster"
      method_option :feed, type: :boolean, default: false,
                           desc: "Use CheckInFeedReport (raw rows) instead of the summary aggregate"
      method_option :wait, type: :boolean, default: true
      method_option :timeout, type: :numeric, default: 300, desc: "Max seconds to wait"
      def summary
        report_type = options[:feed] ? "CheckInFeedReport" : "CheckInSummaryReport"
        args = {}
        args["roster_id"] = options[:roster] if options[:roster]

        body = {
          report: {
            type: report_type,
            version: "v1",
            name: "CLI #{report_type} #{options[:start]}..#{options[:end]}",
            start_at: options[:start],
            end_at: options[:end],
            args: args
          }
        }

        report = client.post("/api/v1/reports", body)
        if options[:wait]
          report = Reports.poll(client, report["id"], timeout: options[:timeout])
        end

        render(report,
               summary: "#{report_type} ##{report["id"]} status=#{report["status"]}.",
               breadcrumbs: [
                 { "cmd" => "wiq reports show #{report["id"]}", "description" => "Refetch later" },
                 { "cmd" => "wiq reports types", "description" => "See other recommended report types" }
               ])
      end
    end
  end
end
