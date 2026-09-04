# frozen_string_literal: true

module Wiq
  module Commands
    class ProspectFamilies < Base
      SORT_OPTIONS = %w[newest oldest_followup oldest_contact next_trial].freeze
      ACTIVITY_TYPES = %w[phone_call sms email in_person other].freeze

      desc "list", "List prospect families (one row per household)"
      long_desc <<~DESC
        Returns one row per family (household). Each row embeds:
          - All the family's prospects (one per kid) inline
          - The most recent `last_contact` note (activity_type, author,
            occurred_at) preloaded as has_one
          - The family's registration_answers, with question prompts

        `--query` searches BOTH family contact (name, email, phone — with
        digit-stripped phone matching) AND child first/last names via a
        subquery on the prospects table. A "Johnny" search matches either
        a parent named Johnny OR a child named Johnny; you'll see which
        from the `child_first_name` field on the embedded prospects.

        Filters mirror `wiq prospects list`, plus:
          --question-id <id> + --answer-value <str>   Filter by a specific
                                                       registration answer
                                                       (both flags required)
          --sort                                       newest (default for
                                                       "All Leads"),
                                                       oldest_followup
                                                       (default when
                                                       --attention=needs_attention),
                                                       oldest_contact (NULLs
                                                       first — never-contacted
                                                       families surface), or
                                                       next_trial
      DESC
      method_option :query, type: :string,
                            desc: "Free-text search (bypasses other filters)"
      method_option :attention, type: :string, enum: Prospects::ATTENTION_MODES,
                                desc: "Pipeline cut: needs_attention or handled"
      method_option :stage, type: :string, enum: Prospects::STAGES,
                            desc: "Families with at least one prospect in this stage"
      method_option :assigned_to_me, type: :boolean, default: false,
                                     desc: "Only families assigned to the calling coach"
      method_option :assigned_coach, type: :numeric,
                                     desc: "Only families assigned to this coach_profile id"
      method_option :question_id, type: :numeric,
                                  desc: "Registration question id to filter by (pair with --answer-value)"
      method_option :answer_value, type: :string,
                                   desc: "Registration answer value (pair with --question-id)"
      method_option :sort, type: :string, enum: SORT_OPTIONS,
                           desc: "Override default sort. Default depends on --attention."
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
          if options[:question_id] && options[:answer_value]
            params["question_id"] = options[:question_id]
            params["answer_value"] = options[:answer_value]
          elsif options[:question_id] || options[:answer_value]
            raise Wiq::Error.new("--question-id and --answer-value must be passed together.",
                                 code: "missing_question_pair")
          end
        end
        params["sort"] = options[:sort] if options[:sort]

        records, total = fetch_index("/api/v1/prospect_families", params, key: "prospect_families")
        render_index(
          records, total: total,
          summary: "Listed #{records.size} prospect families.",
          breadcrumbs: [
            { "cmd" => "wiq prospect_families show <id>", "description" => "Drill into one family" },
            { "cmd" => "wiq prospect_families notes <id>", "description" => "See contact log" },
            { "cmd" => "wiq prospects summary", "description" => "Pipeline dashboard" }
          ]
        )
      end

      desc "show ID", "Fetch a single prospect family"
      long_desc <<~DESC
        Full family payload: contact info (name/email/phone), source
        ("How did you hear about us?"), linked guardian (parent profile),
        assigned coach, the most recent `last_contact` summary, every
        prospect (kid) sorted by created_at, and every registration_answer
        with its question prompt.
      DESC
      def show(id)
        family = client.get("/api/v1/prospect_families/#{id}")
        render(family,
               summary: "Family #{family["id"]} — #{family["contact_name"]} (#{family["prospects"].size} prospects).",
               breadcrumbs: [
                 { "cmd" => "wiq prospect_families notes #{family["id"]}",
                   "description" => "See contact log for this family" },
                 { "cmd" => "wiq prospects show <prospect_id>", "description" => "Drill into one kid" }
               ])
      end

      desc "notes FAMILY_ID", "List notes / contact log for a prospect family"
      long_desc <<~DESC
        Contact log for a family — every Note row with
        noteable_type=ProspectFamily, sorted newest-first. Each row:
        author (name + profile type), created_at, activity_type
        (e.g. phone_call, email, text, in_person, dm), and the note
        body in both rich content + plain_content.
      DESC
      method_option :all, type: :boolean, default: false
      def notes(family_id)
        records, total = fetch_index("/api/v1/prospect_families/#{family_id}/notes",
                                     { "per_page" => 50 },
                                     key: "notes")
        render_index(
          records, total: total,
          summary: "Listed #{records.size} notes for family #{family_id}.",
          breadcrumbs: [
            { "cmd" => "wiq prospect_families show #{family_id}", "description" => "Back to the family" }
          ]
        )
      end

      desc "stage_changes FAMILY_ID", "Stage-transition audit log for every prospect in a family"
      long_desc <<~DESC
        Append-only history of every stage move for every prospect (kid)
        in the family, newest first. Each row: prospect_id + child_name,
        from_stage (null on the initial create), to_stage, changed_at,
        changed_via, and changed_by (profile, or null for system moves).

        changed_via values:
          manual              A person moved it (drawer, note shortcut, or a
                              PAT write — changed_by names the coach)
          trial_registration  Family bought a trial session
          check_in            Kid checked in to a trial practice
          trial_expired       Trial passes ran out
          paid_registration   Registered for a paid session (→ converted)
          subscription        Started a recurring membership (→ converted)
          backfill            Historical import
          bulk_archive        The stale-lead archive task

        Use this to answer "did this lead actually trial or skip straight
        to converted?" — the prospect row only carries its CURRENT stage —
        and to review what an agent or coach did before attempting another
        `wiq prospects advance` (moves are forward-only via PAT).
      DESC
      method_option :all, type: :boolean, default: false
      def stage_changes(family_id)
        records, total = fetch_index("/api/v1/prospect_families/#{family_id}/stage_changes",
                                     { "per_page" => 50 },
                                     key: "stage_changes")
        render_index(
          records, total: total,
          summary: "Listed #{records.size} stage changes for family #{family_id}.",
          breadcrumbs: [
            { "cmd" => "wiq prospect_families show #{family_id}", "description" => "Back to the family" },
            { "cmd" => "wiq prospect_families notes #{family_id}", "description" => "Contact log alongside the stage history" }
          ]
        )
      end

      desc "linked_answers FAMILY_ID", "Registration answers on the member profiles linked to a family"
      long_desc <<~DESC
        Trial-purchase leads skip the interest form, so their phone number
        and other intake details usually exist only as registration answers
        on the profiles the family is linked to: the guardian (parent or
        coach) and each prospect's wrestler_profile. This returns one entry
        per linked profile (profile_id, profile_type, full_name, relation =
        guardian | wrestler) with its registration_answers, deduped to the
        most recent answer per question and ordered by the question's
        display order.

        Not paginated. Coach visibility is enforced server-side, so
        admin-only questions are omitted for non-admin tokens. A family
        with no linked profiles returns an empty list.

        Cheaper first stop: `wiq prospect_families show` already surfaces
        `phone_suggestions` for blank-phone families. Use this when you
        need everything known about the household before a call.
      DESC
      def linked_answers(family_id)
        data = client.get("/api/v1/prospect_families/#{family_id}/linked_answers")
        profiles = Array(data["linked_profiles"])
        answer_count = profiles.sum { |p| Array(p["registration_answers"]).size }
        render_index(
          profiles,
          summary: "#{profiles.size} linked profiles with #{answer_count} visible registration answers for family #{family_id}.",
          breadcrumbs: [
            { "cmd" => "wiq prospect_families show #{family_id}", "description" => "Back to the family" },
            { "cmd" => "wiq prospect_families update #{family_id} --phone <number>",
              "description" => "Copy a found phone onto the family record" }
          ]
        )
      end

      desc "create", "Create a prospect family (household) [prospects:write]"
      long_desc <<~DESC
        POSTs to /api/v1/prospect_families. Requires a coach PAT minted
        with the prospects:write scope on a team that has enabled it
        (Settings → API Access). Only --first-name is required; --email
        must be a valid address when given.

        A family is the household record — add the kid(s) afterwards with
        `wiq prospects create <family_id> --first-name ...`. Check for an
        existing household first with `wiq prospect_families list --query
        <name or email or phone>` to avoid duplicates.

        --source is the machine-readable origin (e.g. web_form, walk_in,
        referral); --hear-about-us is the family's free-text answer to
        "How did you hear about us?". --assigned-coach takes a
        coach_profile id. --guardian-id/--guardian-type link an existing
        ParentProfile or CoachProfile as the guardian.
      DESC
      method_option :first_name, type: :string, required: true, desc: "contact_first_name (required)"
      method_option :last_name, type: :string, desc: "contact_last_name"
      method_option :email, type: :string, desc: "contact_email"
      method_option :phone, type: :string, desc: "contact_phone"
      method_option :hear_about_us, type: :string, desc: "Free-text 'How did you hear about us?'"
      method_option :source, type: :string, desc: "Lead source tag (free text)"
      method_option :assigned_coach, type: :numeric, desc: "assigned_coach_id (coach_profile id)"
      method_option :guardian_id, type: :numeric, desc: "Existing profile id to link as guardian"
      method_option :guardian_type, type: :string, enum: %w[ParentProfile CoachProfile],
                                    desc: "Profile type for --guardian-id"
      def create
        family = client.post("/api/v1/prospect_families", { "prospect_family" => build_family_attrs })
        render(family,
               summary: "Created prospect family #{family["id"]} — #{family["contact_name"]}.",
               breadcrumbs: [
                 { "cmd" => "wiq prospects create #{family["id"]} --first-name <child>",
                   "description" => "Add the kid(s) to this household" },
                 { "cmd" => "wiq prospect_families note #{family["id"]} --activity-type phone_call --content \"...\"",
                   "description" => "Log the first contact" }
               ])
      end

      desc "update ID", "Edit a prospect family's contact info or assignment [prospects:write]"
      long_desc <<~DESC
        PATCHes /api/v1/prospect_families/:id with only the flags you
        pass. Requires the prospects:write scope (team-enabled + on the
        token). Typical uses: fill in a missing phone (see
        `phone_suggestions` on `wiq prospect_families show`), reassign a
        coach, or correct a misspelled name.
      DESC
      method_option :first_name, type: :string, desc: "contact_first_name"
      method_option :last_name, type: :string, desc: "contact_last_name"
      method_option :email, type: :string, desc: "contact_email"
      method_option :phone, type: :string, desc: "contact_phone"
      method_option :hear_about_us, type: :string, desc: "Free-text 'How did you hear about us?'"
      method_option :source, type: :string, desc: "Lead source tag (free text)"
      method_option :assigned_coach, type: :numeric, desc: "assigned_coach_id (coach_profile id)"
      method_option :guardian_id, type: :numeric, desc: "Existing profile id to link as guardian"
      method_option :guardian_type, type: :string, enum: %w[ParentProfile CoachProfile],
                                    desc: "Profile type for --guardian-id"
      def update(id)
        attrs = build_family_attrs
        if attrs.empty?
          raise Wiq::Error.new("Nothing to update — pass at least one field flag.",
                               code: "no_fields",
                               hint: "See `wiq prospect_families update --help` for the editable fields.")
        end

        family = client.patch("/api/v1/prospect_families/#{id}", { "prospect_family" => attrs })
        render(family,
               summary: "Updated prospect family #{family["id"]} — #{family["contact_name"]}.",
               breadcrumbs: [
                 { "cmd" => "wiq prospect_families show #{family["id"]}", "description" => "Refetch the family" }
               ])
      end

      desc "note FAMILY_ID", "Log a contact / add a note to a prospect family [prospects:write]"
      long_desc <<~DESC
        POSTs to /api/v1/prospect_families/:family_id/notes. Requires the
        prospects:write scope (team-enabled + on the token). The note is
        authored by the coach who minted the token.

        --activity-type marks the note as a logged contact: the server
        bumps last_contacted_at on every ACTIVE prospect in the family,
        which is what clears "stale contact" follow-up flags. Omit it for
        an internal note that shouldn't count as contact.

        Side effects in the same call (prospect ids, comma-separated):
          --clear-follow-up 12,34   Clear the needs_follow_up flag
          --add-follow-up 56        Flag for follow-up (reason=manual)
        Ids outside this family are ignored server-side.

        Content is sent as plain text; @mentions are processed server-side.
      DESC
      method_option :content, type: :string, required: true, desc: "Note body (plain text)"
      method_option :activity_type, type: :string, enum: ACTIVITY_TYPES,
                                    desc: "phone_call | sms | email | in_person | other (omit for a plain note)"
      method_option :clear_follow_up, type: :string,
                                      desc: "Comma-separated prospect ids to un-flag for follow-up"
      method_option :add_follow_up, type: :string,
                                    desc: "Comma-separated prospect ids to flag for follow-up"
      def note(family_id)
        body = {
          "note" => {
            "content" => options[:content],
            "plain_content" => options[:content]
          }
        }
        body["note"]["activity_type"] = options[:activity_type] if options[:activity_type]
        clear_ids = parse_id_list(options[:clear_follow_up])
        add_ids = parse_id_list(options[:add_follow_up])
        body["clear_follow_up_for"] = clear_ids unless clear_ids.empty?
        body["add_follow_up_for"] = add_ids unless add_ids.empty?

        note = client.post("/api/v1/prospect_families/#{family_id}/notes", body)
        kind = options[:activity_type] ? "Logged #{options[:activity_type]} contact" : "Added note"
        render(note,
               summary: "#{kind} ##{note["id"]} on family #{family_id}.",
               breadcrumbs: [
                 { "cmd" => "wiq prospect_families notes #{family_id}", "description" => "Full contact log" },
                 { "cmd" => "wiq prospect_families show #{family_id}", "description" => "Back to the family" }
               ])
      end

      no_commands do
        # Maps CLI flags → the `prospect_family` permit list on
        # Api::V1::ProspectFamiliesController.
        FAMILY_FIELD_MAP = {
          first_name: "contact_first_name",
          last_name: "contact_last_name",
          email: "contact_email",
          phone: "contact_phone",
          hear_about_us: "hear_about_us",
          source: "source",
          assigned_coach: "assigned_coach_id",
          guardian_id: "guardian_id",
          guardian_type: "guardian_type"
        }.freeze

        def build_family_attrs
          attrs = {}
          FAMILY_FIELD_MAP.each do |flag, param|
            value = options[flag]
            attrs[param] = value unless value.nil?
          end
          attrs
        end

        def parse_id_list(raw)
          return [] if raw.nil? || raw.to_s.strip.empty?

          raw.to_s.split(",").map(&:strip).reject(&:empty?).map(&:to_i).reject(&:zero?)
        end
      end
    end
  end
end
