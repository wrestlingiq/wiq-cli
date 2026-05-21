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
      long_desc <<~DESC
        Paid sessions are WIQ's registration periods — recurring (monthly
        subscriptions) and one-off (clinics, camps, drop-ins). They're the
        thing you point most finance reports at.

        --type accepts a preset server-side scope:
          registerable, guest_registerable, ends_in_future, recurring,
          recurring_registerable, not_recurring, not_recurring_with_archived,
          not_archived, dropin, trial, trial_or_dropin

        --season filters CLI-side to sessions whose [start_at, end_at] window
        overlaps the given calendar year. Pair with --all to get an exhaustive
        list.

        Each row embeds a `stats` block with registration counts
        (good_standing_registrations_count, overdue_registrations_count,
        not_canceled_registrations_count, good_standing_members_count) so
        you usually don't need a follow-up call.
      DESC
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

        render_index(
          records, total: total,
          summary: "Listed #{records.size} paid sessions#{options[:season] ? " for #{options[:season]}" : ""}.",
          breadcrumbs: [
            { "cmd" => "wiq paid_sessions show <id>", "description" => "Inspect one session" },
            { "cmd" => "wiq reports run PaidSessionAccountingReport --paid-session <id>",
              "description" => "Line-item accounting (admin only)" }
          ]
        )
      end

      desc "show ID", "Fetch a single paid session"
      long_desc <<~DESC
        Full payload includes name, slug, start/end dates, session_type,
        registration_open flag, capacity_limit, welcome/check-in/approval/denial
        text, payment_options, roster_syncers, product + upsell_product,
        and the `stats` count block.
      DESC
      def show(id)
        ps = client.get("/api/v1/paid_sessions/#{id}")
        render(ps,
               summary: "Paid session #{ps["id"]} — #{ps["name"]}",
               breadcrumbs: [
                 { "cmd" => "wiq reports run PaidSessionAccountingReport --paid-session #{ps["id"]}",
                   "description" => "Line-item accounting (admin only)" },
                 { "cmd" => "wiq reports run SessionRegistrationAnswerReport --paid-session #{ps["id"]}",
                   "description" => "Full Q&A export" }
               ])
      end
    end
  end
end
