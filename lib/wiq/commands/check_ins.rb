# frozen_string_literal: true

module Wiq
  module Commands
    class CheckIns < Base
      desc "event EVENT_ID", "List check-ins for an event"
      long_desc <<~DESC
        Every check-in row for a single event. Each row carries the
        wrestler profile, the event reference, the status string
        (free-text — common values: checked_in, absent, late, excused),
        and the registration_answers captured at check-in time.

        Discover event ids via `wiq events list --start ... --end ...`.
      DESC
      method_option :status, type: :string, desc: "Filter by status (Ransack q[status_eq])"
      method_option :all, type: :boolean, default: false, desc: "Follow pagination until exhausted"
      def event(event_id)
        params = { "per_page" => 50 }
        params["q[status_eq]"] = options[:status] if options[:status]
        records, total = fetch_index("/api/v1/events/#{event_id}/check_ins", params, key: "check_ins")
        render_index(
          records, total: total,
          summary: "Listed #{records.size} check-ins for event #{event_id}.",
          breadcrumbs: [
            { "cmd" => "wiq events show #{event_id}", "description" => "See the event itself" }
          ]
        )
      end

      desc "wrestler WRESTLER_ID", "List a wrestler's check-ins"
      long_desc <<~DESC
        Cross-event view: every check-in this wrestler has ever had,
        sorted newest-first. Use --since YYYY-MM-DD to scope.

        For roster-wide attendance use `wiq check_ins summary` or
        `wiq reports run LastPracticeAttendedReport --roster <id>`.
      DESC
      method_option :since, type: :string, desc: "Earliest created_at date (YYYY-MM-DD)"
      method_option :all, type: :boolean, default: false
      def wrestler(wrestler_id)
        params = { "per_page" => 50 }
        params["q[created_at_gteq]"] = options[:since] if options[:since]
        records, total = fetch_index("/api/v1/wrestlers/#{wrestler_id}/check_ins", params, key: "check_ins")
        render_index(
          records, total: total,
          summary: "Listed #{records.size} check-ins for wrestler #{wrestler_id}.",
          breadcrumbs: [
            { "cmd" => "wiq wrestlers show #{wrestler_id}",
              "description" => "See the wrestler's profile" },
            { "cmd" => "wiq reports run LastPracticeAttendedReport --roster <id>",
              "description" => "Find ghost wrestlers across a roster" }
          ]
        )
      end

      desc "summary", "Run a CheckInSummaryReport (default) or CheckInFeedReport for a date range"
      long_desc <<~DESC
        Convenience wrapper around `wiq reports run`. Default report type
        is CheckInSummaryReport — one row per wrestler with totals.
        Pass --feed to switch to CheckInFeedReport (one row per check-in,
        useful for "who came today" or capturing arrival times).

        The CLI submits the report, then polls until status=ready (unless
        --no-wait). Both reports are non-finance, so any CoachProfile PAT
        on the team can run them.

        For Q&A capture at check-in time, use
        `wiq reports run CheckInReport` (the "with questions" variant).
      DESC
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
