# frozen_string_literal: true

module Wiq
  module Commands
    class Prospects < Base
      STAGES = %w[inquiry trial_scheduled trialing trial_complete converted didnt_join archived].freeze
      ATTENTION_MODES = %w[needs_attention handled].freeze

      desc "list", "List individual prospects (one row per kid)"
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
      def show(id)
        prospect = client.get("/api/v1/prospects/#{id}")
        render(prospect,
               summary: "Prospect #{prospect["id"]} — #{prospect["child_first_name"]} #{prospect["child_last_name"]} (stage=#{prospect["stage"]}).")
      end

      desc "summary", "Pipeline dashboard: counts per stage + conversion rate"
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
