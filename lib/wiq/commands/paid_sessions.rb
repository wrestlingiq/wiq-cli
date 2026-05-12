# frozen_string_literal: true

module Wiq
  module Commands
    class PaidSessions < Base
      PRESET_TYPES = %w[
        registerable guest_registerable ends_in_future recurring_registerable
        recurring not_recurring not_recurring_with_archived not_archived
        dropin trial trial_or_dropin
      ].freeze

      desc "list", "List paid sessions"
      method_option :type, type: :string, enum: PRESET_TYPES, desc: "Preset scope filter"
      method_option :season, type: :numeric, desc: "Filter to sessions overlapping calendar year"
      method_option :all, type: :boolean, default: false
      def list
        params = { "per_page" => 50 }
        params[:type] = options[:type] if options[:type]

        records, total = fetch_index("/api/v1/paid_sessions", params, key: "paid_sessions")

        if options[:season]
          year = Integer(options[:season])
          y_start = "#{year}-01-01"
          y_end = "#{year}-12-31"
          records = records.select do |ps|
            (ps["start_at"].to_s <= y_end) && ((ps["end_at"].to_s >= y_start) || ps["end_at"].nil?)
          end
        end

        render_index(records, total: total,
                              summary: "Listed #{records.size} paid sessions#{options[:season] ? " for #{options[:season]}" : ""}.")
      end

      desc "show ID", "Fetch a single paid session"
      def show(id)
        ps = client.get("/api/v1/paid_sessions/#{id}")
        render(ps, summary: "Paid session #{ps["id"]} — #{ps["name"]}")
      end
    end
  end
end
