# frozen_string_literal: true

module Wiq
  module Commands
    class Reports < Base
      # Curated allowlist surfaced in `wiq reports types`. Users can still pass
      # any type string to `run`; this map governs documentation, arg hints,
      # and agent-facing recommendations. Per-entry keys:
      #   args:        permitted args.* keys for this type
      #   dates:       :required | :optional — whether start_at/end_at are needed
      #   desc:        one-line description
      #   recommended: true | false — agents should prefer/avoid this type
      #                (omit when neutral)
      #   prefer:      array of better alternatives (only when recommended: false)
      #   notes:       agent-facing guidance, surfaced in `wiq reports types --agent`
      #   example:     concrete `wiq reports run ...` invocation
      #   admin_only:  true for the 9 finance reports gated by Pundit's
      #                acceptable_finance_permissions? (= is_admin?). Non-finance
      #                reports require a CoachProfile PAT on the team. PATs bound
      #                to ParentProfile or WrestlerProfile 403 on any report POST.
      #
      # Note on auth: "elite" is a Team#account_type (gates UI tab rendering),
      # not a per-user permission — the report POST doesn't check it. Same for
      # "payments_enabled" — that's a team attribute, not a permission flag.
      # The only API-level gate beyond CoachProfile is admin? for finance reports.
      TYPES = {
        # ── Roster tab ───────────────────────────────────────────────
        "RosterReport" => {
          args: %w[roster_id append_property_ids include_archived_roster_tags],
          dates: :optional,
          desc: "Roster snapshot — name, weight class, academic class, age",
          recommended: true,
          notes: "Supports custom columns via --append-properties <q_ids>: pass " \
                 "registration_question ids (discoverable via " \
                 "`wiq registrations questions --visibility public`, plus " \
                 "--visibility private if admin) to surface intake data as " \
                 "extra columns. Skip questions with a deleted_at — they're " \
                 "still in the index payload but won't render. roster_id=0 " \
                 "means \"all rosters\". Each appended question becomes a column.",
          example: "wiq reports run RosterReport --roster 42 --append-properties 17 23"
        },
        "FullExportWrestlerReport" => {
          args: %w[],
          dates: :optional,
          desc: "Full wrestler export — every known field for every wrestler",
          notes: "Very slow on large teams. Prefer RosterReport with " \
                 "--append-properties unless you actually need the exhaustive dump."
        },

        # ── Invite tab ───────────────────────────────────────────────
        "InviteStatusReport" => {
          args: %w[],
          dates: :optional,
          desc: "Wrestlers / parents / coaches invited but not yet account-created",
          recommended: true,
          notes: "Mostly useful for high school teams or anywhere a coach is " \
                 "manually inviting accounts. Club teams should prefer the " \
                 "registration flow — parents register, then invite their own " \
                 "kids — so this report stays empty for them."
        },

        # ── USAW / AAU tab ───────────────────────────────────────────
        "UsawReport" => {
          args: %w[roster_id],
          dates: :optional,
          desc: "All USA Wrestling card info on file, one row per wrestler",
          recommended: true,
          notes: "UI hides this tab when USAW collection is off (team setting)."
        },
        "UsawExpiredReport" => {
          args: %w[roster_id],
          dates: :optional,
          desc: "Wrestlers missing or with expired USAW memberships",
          notes: "Output is also a bulk-purchase upload format for USAW's system."
        },
        "UsawExportReport" => {
          args: %w[roster_id paid_session_id],
          dates: :optional,
          desc: "USAW bulk-purchase upload format",
          notes: "Only report that accepts paid_session_id=0 to mean " \
                 "\"all sessions\"."
        },
        "AauReport" => {
          args: %w[roster_id],
          dates: :optional,
          desc: "All AAU card info on file, one row per wrestler",
          recommended: true,
          notes: "UI hides this tab when AAU collection is off (team setting)."
        },
        "AauExpiredReport" => {
          args: %w[roster_id],
          dates: :optional,
          desc: "Wrestlers missing or with expired AAU memberships"
        },
        "AauExportReport" => {
          args: %w[roster_id],
          dates: :optional,
          desc: "AAU bulk-purchase upload format"
        },

        # ── Stats tab ────────────────────────────────────────────────
        "WinLossReport" => {
          args: %w[roster_id],
          dates: :required,
          desc: "Wins and losses per wrestler",
          recommended: true
        },
        "RosterStatsReport" => {
          args: %w[roster_id],
          dates: :required,
          desc: "Wrestling stats per wrestler (takedowns, nearfall, etc.)",
          recommended: true
        },
        "EventStatsReport" => {
          args: %w[event_id],
          dates: :optional,
          desc: "Per-wrestler stats for a single event",
          notes: "Single-event drill-down. For a date range use RosterStatsReport. " \
                 "Discover event_id via `wiq events list --start ... --end ...`."
        },

        # ── Attendance tab ───────────────────────────────────────────
        "CheckInSummaryReport" => {
          args: %w[roster_id],
          dates: :required,
          desc: "Summarized check-ins for a date range — per-wrestler totals",
          recommended: true,
          notes: "One row per wrestler over the date range — totals across all " \
                 "their check-ins in the window. If you want one row per " \
                 "check-in event use CheckInFeedReport. The UI doesn't expose " \
                 "a roster picker; counts span the whole team.",
          example: "wiq reports run CheckInSummaryReport --start 2026-05-01 --end 2026-05-31"
        },
        "CheckInFeedReport" => {
          args: %w[roster_id],
          dates: :required,
          desc: "Raw check-in feed — one row per check-in, sorted by time",
          recommended: true,
          notes: "Useful for \"who came to the club today and what registrations " \
                 "did they have at check-in time.\" Larger payload than the " \
                 "summary.",
          example: "wiq reports run CheckInFeedReport --start 2026-05-01 --end 2026-05-31"
        },
        "PracticeAttendanceReport" => {
          args: %w[roster_id],
          dates: :required,
          desc: "Practice-event attendance roll-up across a date range",
          recommended: false,
          prefer: %w[CheckInSummaryReport CheckInFeedReport],
          notes: "Primarily used by high school coaches who need a report for " \
                 "their athletic director about who was present vs absent. " \
                 "Only pulls practice events. Not recommended for club teams — " \
                 "use CheckInSummaryReport or CheckInFeedReport instead."
        },
        "LastPracticeAttendedReport" => {
          args: %w[roster_id],
          dates: :optional,
          desc: "Days since last practice attended, per wrestler",
          recommended: true,
          notes: "Useful for following up with people who haven't shown up to " \
                 "practice in a while — particularly for seasonal clubs."
        },
        "ChurnRiskReport" => {
          args: %w[roster_id days_threshold],
          dates: :optional,
          desc: "Active recurring subscribers who haven't checked in within a window",
          recommended: true,
          notes: "Useful for subscription-based clubs to identify who might " \
                 "cancel soon, based on no check-in within a chosen window. " \
                 "Pass --days-threshold (7|14|30|60|90); any other value " \
                 "falls back to the model's 30-day default.",
          example: "wiq reports run ChurnRiskReport --roster 0 --days-threshold 30"
        },
        "CheckInReport" => {
          args: %w[roster_id],
          dates: :required,
          desc: "Extended attendance — one row per check-in INCLUDING Q&A responses",
          notes: "UI labels this \"Attendance Extended (with questions).\" Same " \
                 "shape as CheckInFeedReport PLUS the registration_answer " \
                 "values collected at check-in time. Use when Q&A capture " \
                 "matters; otherwise prefer CheckInFeedReport."
        },

        # ── Subscription tab (admin-gated UI; non-finance reports below
        # only require coach access at the API level) ────────────────
        "MembershipSummaryReport" => {
          args: %w[],
          dates: :optional,
          desc: "Every subscription ever created, one row each",
          recommended: true,
          admin_only: true
        },
        "CancelledSubscriptionsReport" => {
          args: %w[],
          dates: :optional,
          desc: "Canceled subscriptions, ordered by cancellation date"
        },
        "CurrentlyPausedSubscriptionsReport" => {
          args: %w[],
          dates: :optional,
          desc: "Currently paused subscriptions, ordered by paused date"
        },
        "ExpiringSubscriptionsReport" => {
          args: %w[],
          dates: :required,
          desc: "Subscriptions expiring in a date range (past or future)",
          recommended: true,
          notes: "Past dates audit churn; future dates plan retention outreach."
        },
        "DiscountedSubscriptionsReport" => {
          args: %w[],
          dates: :optional,
          desc: "Subscriptions (active or canceled) with a scholarship applied"
        },
        "WrestlersWithoutSubscriptionsReport" => {
          args: %w[],
          dates: :optional,
          desc: "Wrestlers without an active recurring subscription"
        },

        # ── Registration tab ────────────────────────────────────────
        "SessionRegistrationAnswerReport" => {
          args: %w[paid_session_id],
          dates: :optional,
          desc: "Full Q&A export of info submitted by parents at signup",
          recommended: true,
          notes: "Pass --paid-session <id> — required."
        },
        "PaidSessionAccountingReport" => {
          args: %w[paid_session_id],
          dates: :optional,
          desc: "Line-item charges for a registration session",
          recommended: true,
          admin_only: true,
          notes: "Pass --paid-session <id> — required."
        },
        "RegistrationFinanceSummaryReport" => {
          args: %w[],
          dates: :required,
          desc: "Financial summary, one row per session"
        },
        "OverdueRegistrationReport" => {
          args: %w[],
          dates: :optional,
          desc: "Overdue installment registrations",
          recommended: true,
          admin_only: true,
          notes: "Standard AR follow-up tool."
        },
        "InProgressRegistrationReport" => {
          args: %w[],
          dates: :optional,
          desc: "Carts that haven't finished signup (abandoned-cart audit)",
          admin_only: true
        },

        # ── Scholarship tab ──────────────────────────────────────────
        "ScholarshipAuditReport" => {
          args: %w[],
          dates: :required,
          desc: "Scholarship code usage across registrations + subscriptions",
          recommended: true,
          admin_only: true
        },

        # ── Donor tab ────────────────────────────────────────────────
        "RecurringDonorReport" => {
          args: %w[],
          dates: :optional,
          desc: "Active recurring donors",
          recommended: true,
          admin_only: true
        },
        "DonationTransactionReport" => {
          args: %w[],
          dates: :required,
          desc: "All payments that included a donation",
          recommended: true,
          admin_only: true
        },

        # ── Fundraiser tab ───────────────────────────────────────────
        "FundraiserSummaryReport" => {
          args: %w[fundraiser_id],
          dates: :optional,
          desc: "Fundraiser results, one row per contributor",
          recommended: true,
          admin_only: true,
          notes: "Pass --fundraiser <id> — required."
        },
        "FundraiserAccountingReport" => {
          args: %w[fundraiser_id],
          dates: :optional,
          desc: "Fundraiser line items, one row per item purchased",
          admin_only: true,
          notes: "Pass --fundraiser <id> — required. Drill-down of " \
                 "FundraiserSummaryReport."
        },

        # ── Online Store tab ─────────────────────────────────────────
        "OnlineStoreSummaryReport" => {
          args: %w[online_store_id],
          dates: :optional,
          desc: "Summary of store orders",
          recommended: true,
          notes: "Pass --online-store <id> — required."
        },
        "OnlineStoreDetailReport" => {
          args: %w[online_store_id],
          dates: :optional,
          desc: "Detailed store orders, one row per line item",
          notes: "Pass --online-store <id> — required. Useful to hand off to a " \
                 "gear or printing partner who needs sku-level data."
        }
      }.freeze

      desc "run TYPE", "Create + (by default) poll a report"
      long_desc <<~DESC
        Submits a report to `POST /api/v1/reports` and (by default) polls
        until status=ready. Returns the full report row including
        `result` (jsonb), which is type-specific output.

        TYPE can be any WIQ report class name. See `wiq reports types` for
        the curated allowlist with recommendations, required args, and
        per-type notes (admin_only flag, special arg semantics, etc.).

        Common args (only those documented in TYPES are honored
        server-side):
          --roster <id>            roster_id (0 = all rosters)
          --paid-session <id>      paid_session_id (0 = all, UsawExport only)
          --event <id>             event_id (EventStatsReport)
          --fundraiser <id>        fundraiser_id (Fundraiser* reports)
          --online-store <id>      online_store_id (OnlineStore* reports)
          --append-properties <ids...>  RosterReport custom columns
          --include-archived-roster-tags  RosterReport tag inclusion
          --days-threshold <7|14|30|60|90>  ChurnRiskReport window
          --season <year>          Resolves to a paid_session_id via the
                                   overlap rule; errors if multiple match

        Polling: 2-second initial interval, exponential backoff to 30s
        cap, default 5-minute timeout. Pass --no-wait to return the
        report row immediately after submission (status=queued or
        processing) and poll later with `wiq reports show <id> --wait`.
      DESC
      method_option :start, type: :string, desc: "YYYY-MM-DD"
      method_option :end, type: :string, desc: "YYYY-MM-DD"
      method_option :roster, type: :numeric, desc: "args.roster_id (0 = all rosters)"
      method_option :paid_session, type: :numeric, desc: "args.paid_session_id"
      method_option :event, type: :numeric, desc: "args.event_id"
      method_option :fundraiser, type: :numeric, desc: "args.fundraiser_id"
      method_option :online_store, type: :numeric, desc: "args.online_store_id"
      method_option :append_properties, type: :array,
                                        desc: "Registration question ids to surface as columns (RosterReport)"
      method_option :include_archived_roster_tags, type: :boolean, default: false,
                                                   desc: "Include archived roster tags (RosterReport)"
      method_option :days_threshold, type: :numeric,
                                     enum: [7, 14, 30, 60, 90],
                                     desc: "args.days_threshold (ChurnRiskReport)"
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
      long_desc <<~DESC
        Fetches a report by id. Pass --wait to poll until status=ready,
        useful for "I kicked this off earlier, is it done yet?" flows.
      DESC
      method_option :wait, type: :boolean, default: false
      method_option :timeout, type: :numeric, default: 300
      def show(id)
        report = options[:wait] ? self.class.poll(client, id, timeout: options[:timeout])
                                : client.get("/api/v1/reports/#{id}")
        render(report,
               summary: "Report ##{report["id"]} status=#{report["status"]}.",
               breadcrumbs: [
                 { "cmd" => "wiq reports show #{id} --wait", "description" => "Poll until ready" }
               ])
      end

      desc "types", "Print the curated report-type allowlist with recommendations"
      long_desc <<~DESC
        Dumps the curated TYPES allowlist with per-entry metadata:
        description, permitted args, whether dates are required, the
        recommended/preferred status, and an example invocation where
        applicable.

        Recommended starting point for any agent trying to pick a report
        for a user question — read this once, then call
        `wiq reports run <TYPE>` with the documented args.

        Entries with `admin_only: true` (the 9 finance reports) require
        an admin CoachProfile PAT. Non-admin coach PATs 403 on those.
      DESC
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
          row["admin_only"] = info[:admin_only] if info[:admin_only]
          row["notes"] = info[:notes] if info[:notes]
          row["example"] = info[:example] if info[:example]
          row
        end
        render_index(
          rows,
          summary: "Documented report types. Auth: every report POST requires a " \
                   "CoachProfile-bound PAT on the team. The 9 entries with " \
                   "admin_only: true additionally require admin? — " \
                   "non-admin coach PATs 403 on those. recommended: true rows " \
                   "are WIQ-blessed picks; prefer: lists alternatives for " \
                   "de-emphasized types.",
          breadcrumbs: [
            { "cmd" => "wiq reports run <TYPE>", "description" => "Submit a report" },
            { "cmd" => "wiq registrations questions",
              "description" => "Discover question ids for RosterReport --append-properties" }
          ]
        )
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
          args["roster_id"] = options[:roster] if options[:roster] || options[:roster] == 0
          args["paid_session_id"] = options[:paid_session] if options[:paid_session] || options[:paid_session] == 0
          args["event_id"] = options[:event] if options[:event]
          args["fundraiser_id"] = options[:fundraiser] if options[:fundraiser]
          args["online_store_id"] = options[:online_store] if options[:online_store]
          if options[:append_properties] && !options[:append_properties].empty?
            args["append_property_ids"] = options[:append_properties].map(&:to_i)
          end
          args["include_archived_roster_tags"] = true if options[:include_archived_roster_tags]
          args["days_threshold"] = options[:days_threshold] if options[:days_threshold]
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
