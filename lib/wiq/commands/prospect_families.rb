# frozen_string_literal: true

module Wiq
  module Commands
    class ProspectFamilies < Base
      SORT_OPTIONS = %w[newest oldest_followup oldest_contact next_trial].freeze

      desc "list", "List prospect families (one row per household)"
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
        render_index(records, total: total,
                              summary: "Listed #{records.size} prospect families.")
      end

      desc "show ID", "Fetch a single prospect family"
      def show(id)
        family = client.get("/api/v1/prospect_families/#{id}")
        render(family,
               summary: "Family #{family["id"]} — #{family["contact_name"]} (#{family["prospects"].size} prospects).",
               breadcrumbs: [
                 { "cmd" => "wiq prospect_families notes #{family["id"]}",
                   "description" => "See contact log for this family" }
               ])
      end

      desc "notes FAMILY_ID", "List notes / contact log for a prospect family"
      method_option :all, type: :boolean, default: false
      def notes(family_id)
        records, total = fetch_index("/api/v1/prospect_families/#{family_id}/notes",
                                     { "per_page" => 50 },
                                     key: "notes")
        render_index(records, total: total,
                              summary: "Listed #{records.size} notes for family #{family_id}.")
      end
    end
  end
end
