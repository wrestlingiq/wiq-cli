# frozen_string_literal: true

module Wiq
  module Commands
    class Prospects < Base
      STAGES = %w[inquiry trial_scheduled trialing trial_complete converted didnt_join archived].freeze
      ATTENTION_MODES = %w[needs_attention handled].freeze

      desc "list", "List individual prospects (one row per kid)"
      long_desc <<~DESC
        Returns one row per prospect (kid), sorted newest-first.

        Funnel stages: inquiry → trial_scheduled → trialing →
        trial_complete → converted (terminal) | didnt_join (terminal) |
        archived (terminal).

        Filters:
          --query              Free-text search across BOTH family contact
                               (name/email/phone) AND child first/last
                               name. Backed by the ProspectFamily.search
                               scope which unions both via a subquery.
                               When set, ALL other filters are bypassed
                               server-side.

                               KNOWN BUG: `wiq prospects list --query …`
                               currently returns HTTP 500 due to an
                               ambiguous-column ORDER BY on the
                               prospect↔prospect_family join. Workaround:
                               use `wiq prospect_families list --query …`
                               instead (same search scope, same matches,
                               returns the family with its prospects
                               nested inline).
          --attention          needs_attention | handled
          --stage              One funnel stage
          --assigned-to-me     Only families assigned to the calling coach
          --assigned-coach <id>  Same, for any coach by id

        Pair with `wiq prospect_families list` to see leads at the
        household level instead.
      DESC
      method_option :query, type: :string,
                            desc: "Free-text search across family name/email/phone (bypasses other filters)"
      method_option :attention, type: :string, enum: ATTENTION_MODES,
                                desc: "Pipeline cut: needs_attention or handled"
      method_option :stage, type: :string, enum: STAGES,
                            desc: "Filter to one funnel stage"
      method_option :assigned_to_me, type: :boolean, default: false,
                                     desc: "Only prospects on a family assigned to the calling coach"
      method_option :assigned_coach, type: :numeric,
                                     desc: "Only prospects on a family assigned to this coach_profile id"
      method_option :all, type: :boolean, default: false
      def list
        params = { "per_page" => 50 }
        if options[:query]
          params["query"] = options[:query]
        else
          params["attention_mode"] = options[:attention] if options[:attention]
          params["stage"] = options[:stage] if options[:stage]
          if options[:assigned_to_me]
            params["assigned_to"] = "me"
          elsif options[:assigned_coach]
            params["assigned_coach_id"] = options[:assigned_coach]
          end
        end

        records, total = fetch_index("/api/v1/prospects", params, key: "prospects")
        render_index(records, total: total,
                              summary: "Listed #{records.size} prospects.",
                              breadcrumbs: breadcrumbs)
      end

      desc "show ID", "Fetch a single prospect"
      long_desc <<~DESC
        Full prospect payload: child name + DOB + academic class,
        experience_level, current stage + stage_changed_at, all the
        funnel timestamps (trial_scheduled_at, trial_completed_at,
        converted_at, archived_at), needs_follow_up + follow_up_reason,
        days_in_stage and days_since_follow_up, plus the linked
        wrestler_profile (if converted), paid_session (if trialing),
        and conversion_billing_subscription with plan name (if converted
        on a recurring sub).
      DESC
      def show(id)
        prospect = client.get("/api/v1/prospects/#{id}")
        render(prospect,
               summary: "Prospect #{prospect["id"]} — #{prospect["child_first_name"]} #{prospect["child_last_name"]} (stage=#{prospect["stage"]}).",
               breadcrumbs: [
                 { "cmd" => "wiq prospect_families show #{prospect["prospect_family_id"]}",
                   "description" => "Family this prospect belongs to" },
                 { "cmd" => "wiq prospect_families notes #{prospect["prospect_family_id"]}",
                   "description" => "Contact log for the family" }
               ])
      end

      desc "summary", "Pipeline dashboard: counts per stage + conversion rate"
      long_desc <<~DESC
        Single-call dashboard. Returns an unwrapped object (not paginated)
        with stage-bucketed counts, needs-action totals, family totals,
        and an aggregate conversion_rate.

        Cohort options for the conversion calculation:
          --start-date / --end-date    Explicit window (must be paired)
          --conversion-days N          Look-back of 30, 60, 90, or 180
                                       days (default 90)

        Both numerator and denominator are pinned to the same cohort
        (prospects created in the window). Without that pin, an old
        prospect converting now would push the rate past 100%.

        Best agent entry point for "how's our pipeline?" — single round
        trip, structured numbers.
      DESC
      method_option :start_date, type: :string,
                                 desc: "Cohort window start (YYYY-MM-DD). Requires --end-date."
      method_option :end_date, type: :string,
                               desc: "Cohort window end (YYYY-MM-DD). Requires --start-date."
      method_option :conversion_days, type: :numeric, enum: [30, 60, 90, 180],
                                      desc: "Look-back window in days when no explicit dates (default 90)"
      def summary
        params = {}
        if options[:start_date] && options[:end_date]
          params["start_date"] = options[:start_date]
          params["end_date"] = options[:end_date]
        elsif options[:start_date] || options[:end_date]
          raise Wiq::Error.new("--start-date and --end-date must be passed together.",
                               code: "missing_cohort_dates")
        end
        params["conversion_days"] = options[:conversion_days] if options[:conversion_days]

        data = client.get("/api/v1/prospects/summary", params)
        render(data,
               summary: "Prospect pipeline: #{data["needs_action_count"]} need action, " \
                        "#{data["active_trials_count"]} active trials, " \
                        "conversion=#{data["conversion_rate"]}%.",
               breadcrumbs: [
                 { "cmd" => "wiq prospects list --attention needs_attention",
                   "description" => "Drill into leads needing action" },
                 { "cmd" => "wiq prospect_families list --sort oldest_followup",
                   "description" => "Queue of families ordered by stalest follow-up" }
               ])
      end

      no_commands do
        def breadcrumbs
          [
            { "cmd" => "wiq prospects summary", "description" => "Pipeline dashboard" },
            { "cmd" => "wiq prospect_families list", "description" => "List by family instead of by kid" }
          ]
        end
      end
    end
  end
end
