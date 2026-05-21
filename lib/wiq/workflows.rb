# frozen_string_literal: true

module Wiq
  # Named multi-step recipes mapping a human question to a CLI command
  # sequence. Discovery via `wiq workflows list` / `wiq workflows show NAME`.
  #
  # Per-entry schema:
  #   name         kebab-case slug (the lookup key — also keys the hash)
  #   category     one of CATEGORIES (used to group `list` output)
  #   question     natural-language framing — what an agent matches against
  #   parameters   structured list of placeholders:
  #                  [{ name:, type:, required:, default?:, enum?:, description?: }]
  #                type is one of "date", "integer", "string"
  #   recipe       ordered list of command strings using two substitution
  #                conventions:
  #                  <name>          → required substitution (must match a
  #                                    declared required parameter)
  #                  [--flag <name>] → optional bracket; drop the whole
  #                                    expression if the parameter is unset
  #   admin_only   true when the workflow depends on at least one admin-only
  #                report or admin-only metric (non-admin coach PATs 403)
  #   notes        agent-facing guidance (when relevant)
  module Workflows
    CATEGORIES = %w[attendance leads roster finance memberships fundraising store].freeze

    ALL = {
      # ── Attendance / check-ins ──────────────────────────────────
      "attendance-last-month" => {
        name: "attendance-last-month",
        category: "attendance",
        question: "How many practices did each wrestler attend last month?",
        parameters: [
          { name: "start_date", type: "date", required: true },
          { name: "end_date", type: "date", required: true },
          { name: "roster_id", type: "integer", required: false, default: 0,
            description: "0 = all rosters" }
        ],
        recipe: [
          "wiq reports run CheckInSummaryReport --start <start_date> --end <end_date> [--roster <roster_id>]"
        ],
        notes: "Useful to build a leaderboard of check-ins at your wrestling club."
      },

      "who-came-today" => {
        name: "who-came-today",
        category: "attendance",
        question: "Who showed up at the club today?",
        parameters: [
          { name: "today_date", type: "date", required: true,
            description: "Today's date in the team's timezone (YYYY-MM-DD)" }
        ],
        recipe: [
          "wiq reports run CheckInFeedReport --start <today_date> --end <today_date>"
        ],
        notes: "The feed includes registration type per check-in, so the agent " \
               "can filter the result client-side to answer follow-ups like " \
               "'who used a trial pass today' or 'who came without an active " \
               "subscription'."
      },

      "churn-risk" => {
        name: "churn-risk",
        category: "attendance",
        question: "Which subscribers are at risk of canceling because they haven't checked in lately?",
        parameters: [
          { name: "days_threshold", type: "integer", required: true,
            enum: [7, 14, 30, 60, 90],
            description: "Window of inactivity, in days. Any value outside the enum falls back to 30." }
        ],
        recipe: [
          "wiq reports run ChurnRiskReport --roster 0 --days-threshold <days_threshold>"
        ]
      },

      # ── Leads pipeline (Prospect is the internal name) ──────────
      "overdue-followups" => {
        name: "overdue-followups",
        category: "leads",
        question: "Which lead families have a stale follow-up?",
        parameters: [],
        recipe: [
          "wiq prospect_families list --attention needs_attention --sort oldest_followup"
        ],
        notes: "WIQ calls these 'prospects' internally but 'leads' in the UI — " \
               "both terms refer to the same thing."
      },

      # ── Roster ops ──────────────────────────────────────────────
      "growth-across-seasons" => {
        name: "growth-across-seasons",
        category: "roster",
        question: "How has roster size changed across seasons?",
        parameters: [
          { name: "year_a", type: "integer", required: true,
            description: "Earlier season year (e.g. 2025)" },
          { name: "year_b", type: "integer", required: true,
            description: "Later season year (e.g. 2026)" }
        ],
        recipe: [
          "wiq paid_sessions list --season <year_a>",
          "wiq rosters list --season <year_a>",
          "wiq paid_sessions list --season <year_b>",
          "wiq rosters list --season <year_b>"
        ],
        notes: "Client-side compare — no first-class growth report exists. " \
               "Clubs are typically seasonal, so the natural comparison is " \
               "season-vs-season (e.g. 2025 season vs 2026 season). Before " \
               "running, clarify whether the user wants a full calendar-year " \
               "diff or a specific roster/registration vs another."
      },

      "roster-by-zip" => {
        name: "roster-by-zip",
        category: "roster",
        question: "What zip codes does our roster cover?",
        parameters: [
          { name: "address_question_id", type: "integer", required: true,
            description: "RegAddressQuestion id, discoverable via " \
                         "`wiq registrations questions --visibility public`" },
          { name: "roster_id", type: "integer", required: false, default: 0,
            description: "0 = all rosters; pass a specific id to scope" }
        ],
        recipe: [
          "wiq registrations questions --visibility public",
          "wiq reports run RosterReport --roster <roster_id> --append-properties <address_question_id>"
        ],
        notes: "Address (with zip) is captured via a registration question, " \
               "not stored on the wrestler directly. RosterReport with " \
               "--append-properties surfaces it as a column. Step 1 of the " \
               "recipe discovers the question id if the agent doesn't know it."
      },

      # ── Finance (admin-only) ────────────────────────────────────
      "revenue-snapshot" => {
        name: "revenue-snapshot",
        category: "finance",
        question: "How are we doing financially over the last quarter?",
        parameters: [],
        recipe: [
          "wiq metrics show net_volume --range 3m",
          "wiq metrics show mrr --range 3m",
          "wiq metrics show active_subscribers --range 3m"
        ],
        admin_only: true,
        notes: "Three calls because we deliberately didn't ship a `metrics " \
               "dashboard` convenience command — the agent fans out and " \
               "composes the answer. net_volume and mrr return integer cents."
      },

      "revenue-by-category" => {
        name: "revenue-by-category",
        category: "finance",
        question: "How is revenue broken down across categories (e.g. Level 1 vs Level 2 subscriptions)?",
        parameters: [
          { name: "range", type: "string", required: false, default: "3m",
            enum: ["today", "7d", "4w", "3m", "12m", "year to date", "custom"],
            description: "Time window for the breakdown." }
        ],
        recipe: [
          "wiq metrics show category_breakdown_net --range <range>"
        ],
        admin_only: true,
        notes: "Returns revenue grouped by category → subcategory → " \
               "detail_category. Common asks: comparing subscription tiers " \
               "(Level 1 vs Level 2), comparing registration revenue vs " \
               "donation revenue, or seeing which revenue source is growing. " \
               "Values are integer cents."
      },

      "paid-session-accounting" => {
        name: "paid-session-accounting",
        category: "finance",
        question: "Give me a line-item breakdown for this registration session.",
        parameters: [
          { name: "paid_session_id", type: "integer", required: true,
            description: "Discoverable via `wiq paid_sessions list`" }
        ],
        recipe: [
          "wiq reports run PaidSessionAccountingReport --paid-session <paid_session_id>"
        ],
        admin_only: true
      },

      "scholarship-audit" => {
        name: "scholarship-audit",
        category: "finance",
        question: "Where is scholarship money going?",
        parameters: [
          { name: "start_date", type: "date", required: true },
          { name: "end_date", type: "date", required: true }
        ],
        recipe: [
          "wiq reports run ScholarshipAuditReport --start <start_date> --end <end_date>"
        ],
        admin_only: true,
        notes: "Also requires team.payments_enabled — the UI hides the tab " \
               "otherwise, but the API just returns empty data."
      },

      # ── Memberships (USAW / AAU) ────────────────────────────────
      "usaw-renewal-batch" => {
        name: "usaw-renewal-batch",
        category: "memberships",
        question: "Which wrestlers need their USAW renewed before our next event?",
        parameters: [
          { name: "roster_id", type: "integer", required: false, default: 0,
            description: "0 = all rosters" }
        ],
        recipe: [
          "wiq reports run UsawExpiredReport [--roster <roster_id>]"
        ],
        notes: "Output is a bulk-purchase upload format usable directly in " \
               "USAW's system."
      },

      "aau-renewal-batch" => {
        name: "aau-renewal-batch",
        category: "memberships",
        question: "Which wrestlers need their AAU memberships renewed?",
        parameters: [
          { name: "roster_id", type: "integer", required: false, default: 0,
            description: "0 = all rosters" }
        ],
        recipe: [
          "wiq reports run AauExpiredReport [--roster <roster_id>]"
        ],
        notes: "Output is a bulk-purchase upload format usable directly in " \
               "AAU's system."
      },

      # ── Fundraising ─────────────────────────────────────────────
      "fundraiser-status" => {
        name: "fundraiser-status",
        category: "fundraising",
        question: "How is our active fundraiser doing?",
        parameters: [
          { name: "fundraiser_id", type: "integer", required: true,
            description: "Discoverable via `wiq fundraisers list` (not yet on the CLI surface — " \
                         "open the WIQ web UI for now)" }
        ],
        recipe: [
          "wiq reports run FundraiserSummaryReport --fundraiser <fundraiser_id>"
        ],
        admin_only: true
      },

      # ── Online store ────────────────────────────────────────────
      "store-orders" => {
        name: "store-orders",
        category: "store",
        question: "What's been sold in our online store?",
        parameters: [
          { name: "online_store_id", type: "integer", required: true,
            description: "Discoverable via the WIQ web UI (not yet on the CLI surface)" }
        ],
        recipe: [
          "wiq reports run OnlineStoreSummaryReport --online-store <online_store_id>"
        ],
        admin_only: true
      }
    }.freeze
  end
end
