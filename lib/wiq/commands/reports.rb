# frozen_string_literal: true

module Wiq
  module Commands
    class Reports < Base
      # Curated allowlist surfaced in `wiq reports types`. Users can still pass any
      # type string to `run`; this map governs documentation, arg hints, and
      # agent-facing recommendations. Per-entry keys:
      #   args:        permitted `args.*` keys for this type
      #   dates:       :required | :optional — whether start_at/end_at are needed
      #   desc:        one-line description
      #   recommended: true | false — agents should prefer/avoid this type
      #                (omit when neutral)
      #   prefer:      array of better alternatives (only when recommended: false)
      #   notes:       agent-facing guidance, surfaced in `wiq reports types --agent`
      #   example:     concrete `wiq reports run ...` invocation
      TYPES = {
        "CheckInSummaryReport" => {
          args: %w[roster_id], dates: :required,
          desc: "Summarized check-ins for a date range — per-wrestler totals",
          recommended: true,
          notes: "WIQ-recommended for attendance questions ('who has attended how many practices?'). " \
                 "Aggregates server-side; smaller payload than the feed.",
          example: "wiq reports run CheckInSummaryReport --start 2026-05-01 --end 2026-05-31 --roster 42"
        },
        "CheckInFeedReport" => {
          args: %w[roster_id], dates: :required,
          desc: "Raw check-in feed — one row per check-in",
          recommended: true,
          notes: "WIQ-recommended when row-level detail matters: timestamps, late arrivals, notes, " \
                 "class_pass usage. Larger payload than the summary.",
          example: "wiq reports run CheckInFeedReport --start 2026-05-01 --end 2026-05-31 --roster 42"
        },
        "PracticeAttendanceReport" => {
          args: %w[roster_id], dates: :required,
          desc: "Legacy attendance roll-up across practices in a date range",
          recommended: false,
          prefer: %w[CheckInSummaryReport CheckInFeedReport],
          notes: "Older format. WIQ team generally recommends Check-In Summary or Check-In Feed " \
                 "instead — same date+roster shape, more useful payload."
        },
        "LastPracticeAttendedReport" => { args: %w[roster_id], dates: :optional, desc: "Most recent attendance per wrestler" },
        "RosterStatsReport" => { args: %w[roster_id], dates: :optional, desc: "Roster composition + counts" },
        "RosterReport" => { args: %w[roster_id], dates: :optional, desc: "Roster membership snapshot" },
        "EventStatsReport" => { args: %w[event_id], dates: :optional, desc: "Per-event statistics" },
        "CheckInReport" => { args: %w[roster_id], dates: :required, desc: "Raw check-ins for a date range" },
        "FullExportWrestlerReport" => { args: %w[], dates: :optional, desc: "Full wrestler export (admin-heavy)" },
        "MembershipSummaryReport" => { args: %w[paid_session_id], dates: :required, desc: "Membership summary for a paid session" },
        "PaidSessionAccountingReport" => { args: %w[paid_session_id], dates: :required, desc: "Accounting roll-up for a paid session" },
        "OverdueRegistrationReport" => { args: %w[], dates: :optional, desc: "Registrations past due" },
        "WrestlersWithoutSubscriptionsReport" => { args: %w[], dates: :optional, desc: "Wrestlers without active subscriptions" },
        "WinLossReport" => { args: %w[roster_id], dates: :required, desc: "Match win/loss aggregation" },
        "DonationTransactionReport" => { args: %w[], dates: :required, desc: "Donation transactions for a date range" },
        "FundraiserSummaryReport" => { args: %w[fundraiser_id], dates: :optional, desc: "Fundraiser summary" },
        "FundraiserAccountingReport" => { args: %w[fundraiser_id], dates: :required, desc: "Fundraiser accounting" },
        "OnlineStoreSummaryReport" => { args: %w[online_store_id], dates: :optional, desc: "Online store summary" },
        "OnlineStoreDetailReport" => { args: %w[online_store_id], dates: :required, desc: "Online store detail" },
        "RecurringDonorReport" => { args: %w[], dates: :optional, desc: "Active recurring donors" },
        "RegistrationFinanceSummaryReport" => { args: %w[paid_session_id], dates: :optional, desc: "Registration finance summary" },
        "ScholarshipAuditReport" => { args: %w[], dates: :optional, desc: "Scholarship audit" }
      }.freeze

      desc "run TYPE", "Create + (by default) poll a report"
      method_option :start, type: :string, desc: "YYYY-MM-DD"
      method_option :end, type: :string, desc: "YYYY-MM-DD"
      method_option :roster, type: :numeric, desc: "args.roster_id"
      method_option :paid_session, type: :numeric, desc: "args.paid_session_id"
      method_option :event, type: :numeric, desc: "args.event_id"
      method_option :fundraiser, type: :numeric, desc: "args.fundraiser_id"
      method_option :online_store, type: :numeric, desc: "args.online_store_id"
      method_option :name, type: :string, desc: "Display name (default: CLI <type> <range>)"
      method_option :season, type: :numeric, desc: "Resolve to paid_session_id via overlap with calendar year"
      method_option :wait, type: :boolean, default: true
      method_option :timeout, type: :numeric, default: 300
      map "run" => :run_report
      def run_report(type)
        args = build_args(type)

        body = {
          report: {
            type: type,
            version: "v1",
            name: options[:name] || default_name(type),
            start_at: options[:start],
            end_at: options[:end],
            args: args
          }
        }

        report = client.post("/api/v1/reports", body)
        report = self.class.poll(client, report["id"], timeout: options[:timeout]) if options[:wait]

        render(report,
               summary: "Report ##{report["id"]} status=#{report["status"]}.",
               breadcrumbs: [
                 { "cmd" => "wiq reports show #{report["id"]}", "description" => "Refetch the result later" }
               ])
      end

      desc "show ID", "Fetch a single report (optionally poll)"
      method_option :wait, type: :boolean, default: false
      method_option :timeout, type: :numeric, default: 300
      def show(id)
        report = options[:wait] ? self.class.poll(client, id, timeout: options[:timeout])
                                : client.get("/api/v1/reports/#{id}")
        render(report, summary: "Report ##{report["id"]} status=#{report["status"]}.")
      end

      desc "types", "Print the curated report-type allowlist with recommendations"
      def types
        rows = TYPES.map do |type, info|
          row = {
            "type" => type,
            "description" => info[:desc],
            "args" => info[:args],
            "dates" => info[:dates].to_s
          }
          row["recommended"] = info[:recommended] if info.key?(:recommended)
          row["prefer"] = info[:prefer] if info[:prefer]
          row["notes"] = info[:notes] if info[:notes]
          row["example"] = info[:example] if info[:example]
          row
        end
        render_index(rows, summary: "Documented report types — `recommended: true` rows are the " \
                                    "WIQ-blessed picks; `prefer:` lists alternatives for de-emphasized types.")
      end

      # Class-level poller used by reports + check_ins summary.
      def self.poll(client, id, timeout: 300, initial: 2, max_interval: 30)
        deadline = Time.now + timeout
        interval = initial
        report = nil
        loop do
          report = client.get("/api/v1/reports/#{id}")
          case report["status"]
          when "ready"
            return report
          when "failed"
            raise Wiq::ReportFailedError, report
          end
          if Time.now >= deadline
            raise Wiq::ReportTimeoutError.new(report, timeout)
          end
          sleep(interval)
          interval = [interval * 2, max_interval].min
        end
      end

      no_commands do
        def build_args(type)
          if options[:season]
            resolver = Wiq::SeasonResolver.new(client)
            matches = resolver.paid_sessions_for(options[:season])
            raise Wiq::SeasonNotFoundError, options[:season] if matches.empty?

            spec = TYPES[type]
            wants_paid_session = spec.nil? || spec[:args].include?("paid_session_id")
            unless wants_paid_session
              raise Wiq::SeasonUnsupportedError.new(type, matches)
            end
            if matches.size > 1 && !options[:paid_session]
              raise Wiq::SeasonUnsupportedError.new(type, matches)
            end
            options[:paid_session] ||= matches.first["id"]
          end

          args = {}
          args["roster_id"] = options[:roster] if options[:roster]
          args["paid_session_id"] = options[:paid_session] if options[:paid_session]
          args["event_id"] = options[:event] if options[:event]
          args["fundraiser_id"] = options[:fundraiser] if options[:fundraiser]
          args["online_store_id"] = options[:online_store] if options[:online_store]
          args
        end

        def default_name(type)
          range = [options[:start], options[:end]].compact.join("..")
          range.empty? ? "CLI #{type}" : "CLI #{type} #{range}"
        end
      end
    end
  end
end
