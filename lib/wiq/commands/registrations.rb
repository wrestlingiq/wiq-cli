# frozen_string_literal: true

module Wiq
  module Commands
    class Registrations < Base
      desc "questions", "List the team's registration questions"
      method_option :all, type: :boolean, default: false
      def questions
        records, total = fetch_index("/api/v1/registration_questions", { "per_page" => 100 }, key: "registration_questions")
        render_index(records, total: total,
                              summary: "Listed #{records.size} registration questions.")
      end

      desc "answers", "List a profile's registration answers"
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
        render_index(records, total: total,
                              summary: "Listed #{records.size} answers for #{options[:profile_type]} #{options[:profile]}.")
      end
    end
  end
end
