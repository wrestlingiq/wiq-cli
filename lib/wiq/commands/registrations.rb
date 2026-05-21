# frozen_string_literal: true

module Wiq
  module Commands
    class Registrations < Base
      desc "questions", "List the team's registration questions"
      long_desc <<~DESC
        Every registration question the team has authored. Useful for:

          - Discovering question ids to pass to
            `wiq reports run RosterReport --append-properties ...`
          - Auditing what the team is collecting at signup
          - Finding the team's address question(s) so you can join zip
            codes (the `RegAddressQuestion` type) to a wrestler

        Each row exposes `prompt`, `type` (e.g. RegTextQuestion,
        RegAddressQuestion, RegYesNoQuestion), `for_type` (who the
        question applies to), `is_public`, `coach_visibility`, and
        `display_order`.

        Skip rows whose `deleted_at` is set — they're still in the index
        payload but no longer asked.
      DESC
      method_option :all, type: :boolean, default: false
      def questions
        records, total = fetch_index("/api/v1/registration_questions", { "per_page" => 100 }, key: "registration_questions")
        render_index(
          records, total: total,
          summary: "Listed #{records.size} registration questions.",
          breadcrumbs: [
            { "cmd" => "wiq reports run RosterReport --append-properties <id1> <id2>",
              "description" => "Surface these as columns on a roster report" }
          ]
        )
      end

      desc "answers", "List a profile's registration answers"
      long_desc <<~DESC
        Returns the registration answers for a specific profile (wrestler,
        parent, or coach). Useful for spot-checking what a family submitted
        at signup.

          --profile-type   WrestlerProfile | ParentProfile | CoachProfile
          --profile        Profile id
          --session        Restrict to a specific paid_session
          --visibility     public | private (admin only for private)

        Privacy note: Pundit gates private answers — a non-admin coach PAT
        will get the public subset only.
      DESC
      method_option :profile, type: :numeric, required: true, desc: "Profile id"
      method_option :profile_type, type: :string, required: true,
                                   enum: %w[WrestlerProfile ParentProfile CoachProfile],
                                   desc: "Profile class"
      method_option :session, type: :numeric, desc: "Restrict to a paid session id"
      method_option :visibility, type: :string, enum: %w[public private], desc: "Visibility filter"
      method_option :all, type: :boolean, default: false
      def answers
        params = {
          "profile_id" => options[:profile],
          "profile_type" => options[:profile_type],
          "per_page" => 50
        }
        params["session_id"] = options[:session] if options[:session]
        params["visibility"] = options[:visibility] if options[:visibility]

        records, total = fetch_index("/api/v1/registration_answers", params, key: "registration_answers")
        render_index(
          records, total: total,
          summary: "Listed #{records.size} answers for #{options[:profile_type]} #{options[:profile]}.",
          breadcrumbs: [
            { "cmd" => "wiq registrations questions", "description" => "See the corresponding questions" }
          ]
        )
      end
    end
  end
end
