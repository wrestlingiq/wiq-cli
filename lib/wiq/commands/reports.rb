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
      #   gating:      free-text precondition ("admin", "elite", "payments_enabled",
      #                "usaw_enabled", "aau_enabled", "donations_allowed",
      #                "online_stores_exist") — surfaced so an agent can
      #                anticipate 403s on permission-gated tabs.
      TYPES = {
        # ── Roster tab ───────────────────────────────────────────────
        "RosterReport" => {
          args: %w[roster_id append_property_ids include_archived_roster_tags],
          dates: :optional,
          desc: "Roster snapshot — name, weight class, academic class, age",
          recommended: true,
          notes: "Supports custom columns via --append-properties <q_ids>: pass " \
                 "registration_question ids (discoverable via " \
                 "`wiq registrations questions`) to surface intake data as extra " \
                 "columns. roster_id=0 means \"all rosters\".",
          example: "wiq reports run RosterReport --roster 42 --append-properties 17 23"
        },
        "FullExportWrestlerReport" => {
          args: %w[],
          dates: :optional,
          desc: "Full wrestler export — every known field for every wrestler",
          notes: "Heavy payload. Prefer RosterReport with --append-properties unless " \
                 "you actually need an exhaustive dump."
        },

        # ── Invite tab ───────────────────────────────────────────────
        "InviteStatusReport" => {
          args: %w[],
          dates: :optional,
          desc: "Wrestlers / parents / coaches invited but not yet account-created",
          recommended: true
        },

        # ── USAW / AAU tab ───────────────────────────────────────────
        "UsawReport" => {
          args: %w[roster_id],
          dates: :optional,
          desc: "All USA Wrestling card info on file, one row per wrestler",
          recommended: true,
          notes: "Gating: requires team.usaw_enabled. Returns 403 / empty if USAW " \
                 "collection is turned off."
        },
        "UsawExpiredReport" => {
          args: %w[roster_id],
          dates: :optional,
          desc: "Wrestlers missing or with expired USAW memberships",
          notes: "Gating: team.usaw_enabled. Output is also a bulk-purchase " \
                 "upload format for USAW's system."
        },
        "UsawExportReport" => {
          args: %w[roster_id paid_session_id],
          dates: :optional,
          desc: "USAW bulk-purchase upload format",
          notes: "Gating: team.usaw_enabled. Only report that accepts " \
                 "paid_session_id=0 to mean \"all sessions\"."
        },
        "AauReport" => {
          args: %w[roster_id],
          dates: :optional,
          desc: "All AAU card info on file, one row per wrestler",
          recommended: true,
          notes: "Gating: requires team.aau_enabled."
        },
        "AauExpiredReport" => {
          args: %w[roster_id],
          dates: :optional,
          desc: "Wrestlers missing or with expired AAU memberships",
          notes: "Gating: team.aau_enabled."
        },
        "AauExportReport" => {
          args: %w[roster_id],
          dates: :optional,
          desc: "AAU bulk-purchase upload format",
          notes: "Gating: team.aau_enabled."
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
          notes: "WIQ-recommended for attendance questions. Aggregates " \
                 "server-side; smaller payload than the feed. The UI doesn't " \
                 "expose a roster picker, but roster_id IS accepted via the API.",
          example: "wiq reports run CheckInSummaryReport --start 2026-05-01 --end 2026-05-31 --roster 42"
        },
        "CheckInFeedReport" => {
          args: %w[roster_id],
          dates: :required,
          desc: "Raw check-in feed — one row per check-in, sorted by time",
          recommended: true,
          notes: "WIQ-recommended when row-level detail matters (timestamps, late " \
                 "arrivals, notes, class_pass usage). UI doesn't show a roster " \
                 "picker but the API accepts roster_id.",
          example: "wiq reports run CheckInFeedReport --start 2026-05-01 --end 2026-05-31 --roster 42"
        },
        "PracticeAttendanceReport" => {
          args: %w[roster_id],
          dates: :required,
          desc: "Legacy attendance roll-up across practices in a date range",
          recommended: false,
          prefer: %w[CheckInSummaryReport CheckInFeedReport],
          notes: "Older format, kept for HS coach workflows. WIQ team recommends " \
                 "Check-In Summary or Check-In Feed instead."
        },
        "LastPracticeAttendedReport" => {
          args: %w[roster_id],
          dates: :optional,
          desc: "Days since last practice attended, per wrestler",
          recommended: true,
          notes: "Canonical \"find ghost wrestlers\" tool."
        },
        "ChurnRiskReport" => {
          args: %w[roster_id days_threshold],
          dates: :optional,
          desc: "Active recurring subscribers who haven't checked in within a window",
          recommended: true,
          notes: "Pass --days-threshold (7|14|30|60|90). NOTE: backend permit " \
                 "list does not yet include days_threshold; until the WIQ-app " \
                 "fix ships, the param is silently dropped and the report uses " \
                 "its 30-day default. Proactive churn-prevention tool.",
          example: "wiq reports run ChurnRiskReport --roster 0 --days-threshold 30"
        },
        "CheckInReport" => {
          args: %w[roster_id],
          dates: :required,
          desc: "Extended attendance — one row per check-in INCLUDING Q&A responses",
          notes: "UI labels this \"Attendance Extended (with questions)\". Same " \
                 "shape as CheckInFeedReport PLUS the registration_answer values " \
                 "collected at check-in time. Use when Q&A capture matters; " \
                 "otherwise prefer CheckInFeedReport."
        },

        # ── Subscription tab (elite + admin) ─────────────────────────
        "MembershipSummaryReport" => {
          args: %w[],
          dates: :optional,
          desc: "Every subscription ever created, one row each",
          recommended: true,
          notes: "Gating: requires team.elite? AND admin permission."
        },
        "CancelledSubscriptionsReport" => {
          args: %w[],
          dates: :optional,
          desc: "Canceled subscriptions, ordered by cancellation date",
          notes: "Gating: elite + admin."
        },
        "CurrentlyPausedSubscriptionsReport" => {
          args: %w[],
          dates: :optional,
          desc: "Currently paused subscriptions, ordered by paused date",
          notes: "Gating: elite + admin."
        },
        "ExpiringSubscriptionsReport" => {
          args: %w[],
          dates: :required,
          desc: "Subscriptions expiring in a date range (past or future)",
          recommended: true,
          notes: "Gating: elite + admin. Future dates plan retention outreach; " \
                 "past dates audit what already churned."
        },
        "DiscountedSubscriptionsReport" => {
          args: %w[],
          dates: :optional,
          desc: "Subscriptions (active or canceled) with a scholarship applied",
          notes: "Gating: elite + admin."
        },
        "WrestlersWithoutSubscriptionsReport" => {
          args: %w[],
          dates: :optional,
          desc: "Wrestlers without an active recurring subscription",
          recommended: true,
          notes: "Gating: elite + admin. Standard AR follow-up tool."
        },

        # ── Registration tab (admin) ─────────────────────────────────
        "SessionRegistrationAnswerReport" => {
          args: %w[paid_session_id],
          dates: :optional,
          desc: "Full Q&A export of info submitted by parents at signup",
          recommended: true,
          notes: "Gating: admin. Pass --paid-session <id> — required."
        },
        "PaidSessionAccountingReport" => {
          args: %w[paid_session_id],
          dates: :optional,
          desc: "Line-item charges for a registration session",
          recommended: true,
          notes: "Gating: admin AND team.payments_enabled. " \
                 "Pass --paid-session <id> — required."
        },
        "RegistrationFinanceSummaryReport" => {
          args: %w[],
          dates: :required,
          desc: "Financial summary, one row per session",
          notes: "Gating: admin AND team.payments_enabled."
        },
        "OverdueRegistrationReport" => {
          args: %w[],
          dates: :optional,
          desc: "Overdue installment registrations",
          recommended: true,
          notes: "Gating: admin AND team.payments_enabled. Standard AR tool."
        },
        "InProgressRegistrationReport" => {
          args: %w[],
          dates: :optional,
          desc: "Carts that haven't finished signup (abandoned-cart audit)",
          notes: "Gating: admin AND team.payments_enabled."
        },

        # ── Scholarship tab (admin + payments) ───────────────────────
        "ScholarshipAuditReport" => {
          args: %w[],
          dates: :required,
          desc: "Scholarship code usage across registrations + subscriptions",
          recommended: true,
          notes: "Gating: admin AND team.payments_enabled."
        },

        # ── Donor tab (donations + admin) ────────────────────────────
        "RecurringDonorReport" => {
          args: %w[],
          dates: :optional,
          desc: "Active recurring donors",
          recommended: true,
          notes: "Gating: admin AND (team.donations_allowed OR donation_page_enabled)."
        },
        "DonationTransactionReport" => {
          args: %w[],
          dates: :required,
          desc: "All payments that included a donation",
          recommended: true,
          notes: "Gating: admin AND (team.donations_allowed OR donation_page_enabled)."
        },

        # ── Fundraiser tab (admin) ───────────────────────────────────
        "FundraiserSummaryReport" => {
          args: %w[fundraiser_id],
          dates: :optional,
          desc: "Fundraiser results, one row per contributor",
          recommended: true,
          notes: "Gating: admin. --fundraiser required."
        },
        "FundraiserAccountingReport" => {
          args: %w[fundraiser_id],
          dates: :optional,
          desc: "Fundraiser line items, one row per item purchased",
          notes: "Gating: admin. --fundraiser required. Drill-down of " \
                 "FundraiserSummaryReport."
        },

        # ── Online Store tab (admin + stores exist) ──────────────────
        "OnlineStoreSummaryReport" => {
          args: %w[online_store_id],
          dates: :optional,
          desc: "Summary of store orders",
          recommended: true,
          notes: "Gating: admin AND at least one online store. " \
                 "--online-store required."
        },
        "OnlineStoreDetailReport" => {
          args: %w[online_store_id],
          dates: :optional,
          desc: "Detailed store orders, one row per line item",
          notes: "Gating: admin AND at least one online store. " \
                 "--online-store required. Drill-down of the summary."
        }
      }.freeze

      desc "run TYPE", "Create + (by default) poll a report"
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
                                     desc: "args.days_threshold (ChurnRiskReport; backend permit fix in flight)"
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
