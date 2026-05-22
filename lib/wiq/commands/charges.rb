# frozen_string_literal: true

module Wiq
  module Commands
    class Charges < Base
      # Match Charge.statuses in app/models/charge.rb. Values are
      # integer-backed via Rails enum (`enum status: { successful: 0, failed: 1 }`).
      # Ransack 4.x does NOT auto-translate enum strings on integer columns,
      # so the CLI translates here before sending q[status_eq]. Without this
      # translation Ransack silently drops the predicate and returns every
      # row — the kind of failure that's worse than a 422.
      STATUS_TO_INT = { "successful" => 0, "failed" => 1 }.freeze
      STATUSES = STATUS_TO_INT.keys.freeze
      DEFAULT_PER_PAGE = 50

      desc "list", "List charges (finance: admin coach only)"
      long_desc <<~DESC
        Returns charges (payment attempts) across the team. Useful for
        answering "did this family pay X?" or "what's been failing
        lately?"

        Auth: admin-only (Pundit scope filters non-admin coach PATs to
        empty results, parent/wrestler PATs return 403).

        Filters translate to Ransack server-side:
          --status                 successful | failed (enum is two-valued)
          --billing-profile <id>   q[billing_profile_id_eq] — the
                                   parent/family who paid. Discover via
                                   `wiq billing_profiles show <profile_id>
                                   --profile-type ParentProfile`.
          --chargeable-type <str>  q[chargeable_type_eq] — the kind of
                                   thing paid for. Common values:
                                   BillingSubscriptionInvoice, Registration,
                                   Donation, FundraiserContribution,
                                   OnlineStoreOrder. (Verify against the
                                   actual data — these are model class
                                   names, not strings the API documents.)
          --since <YYYY-MM-DD>     q[created_at_gteq]
          --until <YYYY-MM-DD>     q[created_at_lteq]

        Each row is rich — billing_profile.billable (the person paying),
        chargeable (what they paid for), wrestlers[] (the kids the charge
        is associated with), refunds, payout, coupon, category. Default
        page size is 50 since charges accumulate fast; use --all for
        exhaustive scans (paired with --since to bound the window).

        **Critical caveat for failed-payment analysis.** A `failed` charge
        is NOT actionable on its own — Stripe/Justifi retry subscriptions
        automatically, and customers retry registrations after card
        declines. Always cross-check that no `successful` charge exists
        for the same (billing_profile_id, chargeable_id, chargeable_type)
        tuple AFTER the failure timestamp. See `wiq workflows show
        failed-payments-recent` for the canonical pattern.
      DESC
      method_option :status, type: :string, enum: STATUSES,
                             desc: "Filter to successful or failed charges"
      method_option :billing_profile, type: :numeric,
                                      desc: "Restrict to one billing_profile id"
      method_option :chargeable_type, type: :string,
                                      desc: "Filter by chargeable model name (e.g. BillingSubscriptionInvoice)"
      method_option :since, type: :string, desc: "Earliest created_at (YYYY-MM-DD)"
      method_option :until, type: :string, desc: "Latest created_at (YYYY-MM-DD)"
      method_option :per_page, type: :numeric, default: DEFAULT_PER_PAGE,
                               desc: "Page size (default 50)"
      method_option :all, type: :boolean, default: false,
                          desc: "Follow pagination until exhausted"
      def list
        params = build_list_params
        records, total = fetch_index("/api/v1/charges", params, key: "charges")
        render_index(
          records, total: total,
          summary: "Listed #{records.size} charges#{summary_filters_suffix}.",
          breadcrumbs: [
            { "cmd" => "wiq billing_profiles show <id> --profile-type ParentProfile",
              "description" => "Look up the family behind a billing_profile_id" },
            { "cmd" => "wiq workflows show failed-payments-recent",
              "description" => "Canonical failed-payment cross-check workflow" }
          ]
        )
      end

      no_commands do
        def build_list_params
          params = { "per_page" => options[:per_page] || DEFAULT_PER_PAGE }
          params["q[status_eq]"] = STATUS_TO_INT.fetch(options[:status]) if options[:status]
          params["q[billing_profile_id_eq]"] = options[:billing_profile] if options[:billing_profile]
          params["q[chargeable_type_eq]"] = options[:chargeable_type] if options[:chargeable_type]
          params["q[created_at_gteq]"] = options[:since] if options[:since]
          params["q[created_at_lteq]"] = options[:until] if options[:until]
          params
        end

        def summary_filters_suffix
          bits = []
          bits << "status=#{options[:status]}" if options[:status]
          bits << "billing_profile=#{options[:billing_profile]}" if options[:billing_profile]
          bits << "since=#{options[:since]}" if options[:since]
          bits << "until=#{options[:until]}" if options[:until]
          bits.empty? ? "" : " (#{bits.join(", ")})"
        end
      end
    end
  end
end
