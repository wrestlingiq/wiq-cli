# frozen_string_literal: true

module Wiq
  module Commands
    class Prospects < Base
      STAGES = %w[inquiry trial_scheduled trialing trial_complete converted didnt_join archived].freeze
      TERMINAL_STAGES = %w[converted didnt_join archived].freeze
      ATTENTION_MODES = %w[needs_attention handled].freeze

      # Write capability every create/update/advance below needs. The server
      # checks it per request: the team must have it enabled AND the token
      # must have been minted with it. See `wiq auth status` for scopes.
      WRITE_CAPABILITY = "prospects:write"

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

      desc "create FAMILY_ID", "Add a prospect (kid) to an existing prospect family [prospects:write]"
      long_desc <<~DESC
        POSTs to /api/v1/prospect_families/:family_id/prospects. Requires a
        coach PAT minted with the prospects:write scope on a team that has
        enabled it (Settings → API Access). Only --first-name is required.

        New prospects start at stage `inquiry` unless --stage is given.
        The stage audit row is attributed to the coach who minted the token.

        Create the household first with `wiq prospect_families create` if
        the family doesn't exist yet; use `wiq prospect_families list
        --query <name>` to check.

        Errors you may see:
          capability_disabled_for_team   Team hasn't enabled prospects:write
          token_missing_scope            Token wasn't minted with it — mint a new one
          validation_failed              Server rejected a field (see details)
      DESC
      method_option :first_name, type: :string, required: true, desc: "child_first_name (required)"
      method_option :last_name, type: :string, desc: "child_last_name"
      method_option :dob, type: :string, desc: "child_date_of_birth (YYYY-MM-DD)"
      method_option :academic_class, type: :string, desc: "child_academic_class (free text, e.g. 5th)"
      method_option :experience_level, type: :string, desc: "experience_level (free text, e.g. none / 1 season)"
      method_option :stage, type: :string, enum: STAGES, desc: "Initial stage (default: inquiry)"
      method_option :paid_session, type: :numeric, desc: "paid_session_id of the trial session"
      method_option :trial_event, type: :numeric, desc: "trial_event_id — the practice/event they'll try"
      method_option :trial_scheduled_at, type: :string, desc: "ISO-8601 timestamp"
      method_option :needs_follow_up, type: :boolean, desc: "Flag (or --no-needs-follow-up to clear) for follow-up"
      def create(family_id)
        body = { "prospect" => build_prospect_attrs }
        prospect = client.post("/api/v1/prospect_families/#{family_id}/prospects", body)
        render(prospect,
               summary: "Created prospect #{prospect["id"]} — #{prospect["child_first_name"]} " \
                        "#{prospect["child_last_name"]} (stage=#{prospect["stage"]}) on family #{family_id}.",
               breadcrumbs: [
                 { "cmd" => "wiq prospects show #{prospect["id"]}", "description" => "Refetch the prospect" },
                 { "cmd" => "wiq prospect_families note #{family_id} --activity-type phone_call --content \"...\"",
                   "description" => "Log the first contact" }
               ])
      end

      desc "update ID", "Edit a prospect's details and/or move its stage [prospects:write]"
      long_desc <<~DESC
        PATCHes /api/v1/prospects/:id with only the flags you pass. Requires
        the prospects:write scope (team-enabled + on the token).

        Stage changes via a PAT are FORWARD-ONLY and cannot leave a terminal
        stage (converted, didnt_join, archived). The server answers 422
        (`stage_transition_refused`) rather than silently no-op'ing; a coach
        can force the move in the web app. `wiq prospects advance` is the
        same call with a clearer signature for stage-only moves.

        --needs-follow-up / --no-needs-follow-up also syncs follow_up_set_at
        and follow_up_reason (=manual) server-side so the flag stays
        internally consistent.

        Funnel timestamps (--trial-scheduled-at, --trial-completed-at,
        --converted-at, --archived-at, --last-contacted-at) accept ISO-8601
        and are normally stamped by the stage change itself — pass them
        only to backfill history.
      DESC
      method_option :first_name, type: :string, desc: "child_first_name"
      method_option :last_name, type: :string, desc: "child_last_name"
      method_option :dob, type: :string, desc: "child_date_of_birth (YYYY-MM-DD)"
      method_option :academic_class, type: :string, desc: "child_academic_class"
      method_option :experience_level, type: :string, desc: "experience_level"
      method_option :stage, type: :string, enum: STAGES, desc: "Move to this stage (forward-only via PAT)"
      method_option :lost_reason, type: :string, desc: "Why they didn't join (pairs with --stage didnt_join)"
      method_option :paid_session, type: :numeric, desc: "paid_session_id of the trial session"
      method_option :trial_event, type: :numeric, desc: "trial_event_id"
      method_option :wrestler_profile, type: :numeric, desc: "wrestler_profile_id to link (on conversion)"
      method_option :needs_follow_up, type: :boolean, desc: "Flag (or --no-needs-follow-up to clear) for follow-up"
      method_option :trial_scheduled_at, type: :string, desc: "ISO-8601 timestamp"
      method_option :trial_completed_at, type: :string, desc: "ISO-8601 timestamp"
      method_option :converted_at, type: :string, desc: "ISO-8601 timestamp"
      method_option :archived_at, type: :string, desc: "ISO-8601 timestamp"
      method_option :last_contacted_at, type: :string, desc: "ISO-8601 timestamp"
      def update(id)
        attrs = build_prospect_attrs
        if attrs.empty?
          raise Wiq::Error.new("Nothing to update — pass at least one field flag.",
                               code: "no_fields",
                               hint: "See `wiq prospects update --help` for the editable fields.")
        end

        prospect = client.patch("/api/v1/prospects/#{id}", { "prospect" => attrs })
        render(prospect,
               summary: "Updated prospect #{prospect["id"]} — #{prospect["child_first_name"]} " \
                        "#{prospect["child_last_name"]} (stage=#{prospect["stage"]}).",
               breadcrumbs: [
                 { "cmd" => "wiq prospects show #{prospect["id"]}", "description" => "Refetch the prospect" },
                 { "cmd" => "wiq prospect_families show #{prospect["prospect_family_id"]}",
                   "description" => "Family this prospect belongs to" }
               ])
      end

      desc "advance ID STAGE", "Move a prospect forward to STAGE [prospects:write]"
      long_desc <<~DESC
        Shorthand for `wiq prospects update ID --stage STAGE`. Stage order:

          inquiry → trial_scheduled → trialing → trial_complete
                  → converted | didnt_join | archived   (terminal)

        Via a personal access token the move must go FORWARD in that order
        and cannot start from a terminal stage. Skipping ahead is fine
        (inquiry → converted). Anything else returns 422 with code
        `stage_transition_refused`; a coach can override in the web app.

        --lost-reason is stored alongside a move to didnt_join.
      DESC
      method_option :lost_reason, type: :string, desc: "Why they didn't join (with didnt_join)"
      def advance(id, stage)
        unless STAGES.include?(stage)
          raise Wiq::Error.new("Unknown stage #{stage.inspect}.",
                               code: "invalid_stage",
                               hint: "Valid stages: #{STAGES.join(", ")}")
        end

        attrs = { "stage" => stage }
        attrs["lost_reason"] = options[:lost_reason] if options[:lost_reason]
        prospect = client.patch("/api/v1/prospects/#{id}", { "prospect" => attrs })
        render(prospect,
               summary: "Prospect #{prospect["id"]} — #{prospect["child_first_name"]} " \
                        "#{prospect["child_last_name"]} is now #{prospect["stage"]}.",
               breadcrumbs: [
                 { "cmd" => "wiq prospect_families note #{prospect["prospect_family_id"]} " \
                            "--activity-type other --content \"...\"",
                   "description" => "Log why, so the contact history matches the stage" },
                 { "cmd" => "wiq prospects show #{prospect["id"]}", "description" => "Refetch the prospect" }
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

        # Maps CLI flags → the `prospect` param permit list on
        # Api::V1::ProspectsController. Only flags actually passed land in
        # the body so PATCH stays a partial update.
        FIELD_MAP = {
          first_name: "child_first_name",
          last_name: "child_last_name",
          dob: "child_date_of_birth",
          academic_class: "child_academic_class",
          experience_level: "experience_level",
          stage: "stage",
          lost_reason: "lost_reason",
          paid_session: "paid_session_id",
          trial_event: "trial_event_id",
          wrestler_profile: "wrestler_profile_id",
          trial_scheduled_at: "trial_scheduled_at",
          trial_completed_at: "trial_completed_at",
          converted_at: "converted_at",
          archived_at: "archived_at",
          last_contacted_at: "last_contacted_at"
        }.freeze

        def build_prospect_attrs
          attrs = {}
          FIELD_MAP.each do |flag, param|
            value = options[flag]
            attrs[param] = value unless value.nil?
          end
          # Boolean: Thor sets nil when the flag isn't passed, true/false otherwise.
          unless options[:needs_follow_up].nil?
            attrs["needs_follow_up"] = options[:needs_follow_up]
          end
          attrs
        end
      end
    end
  end
end
