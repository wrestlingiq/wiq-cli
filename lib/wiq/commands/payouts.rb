# frozen_string_literal: true

module Wiq
  module Commands
    class Payouts < Base
      # Payout.status is a plain text column mirroring the billing
      # partner's normalized status — no integer-enum translation needed
      # (unlike Charge.status). Common values below; the column is not
      # constrained server-side, so --status stays free-form.
      COMMON_STATUSES = %w[paid in_transit scheduled].freeze
      BILLING_PARTNERS = %w[stripe justifi].freeze
      DEFAULT_PER_PAGE = 25

      desc "list", "List bank payouts / deposits (finance: admin coach only)"
      long_desc <<~DESC
        Returns payouts — the batched deposits Stripe or Justifi (WIQ
        Payments) sends to the club's bank account. Useful for "when does
        our money arrive?", "what landed in the bank last week?", and
        reconciling a bank statement line against WIQ charges.

        Auth: admin-only (Pundit scope filters non-admin coach PATs to
        empty results; parent/wrestler PATs return 403).

        Filters translate to Ransack server-side (allowlist: deposits_at,
        status, billing_partner, amount, created_at):
          --status <str>           q[status_eq]. Common values: paid,
                                   in_transit, scheduled. Free-form —
                                   the column mirrors the billing
                                   partner's status strings.
          --billing-partner <str>  q[billing_partner_eq] — stripe | justifi
                                   (justifi is branded "WIQ Payments").
          --since <YYYY-MM-DD>     q[deposits_at_gteq]
          --until <YYYY-MM-DD>     q[deposits_at_lteq]

        --since/--until filter on deposits_at (when the money reaches the
        bank), not created_at — that's the date a treasurer reconciling a
        bank statement cares about. Rows come back newest-deposit first.

        Money fields are integer cents. Each row: amount (net deposit),
        payments_count/payments_total, refunds_count/refunds_total,
        fees_total, status, deposits_at, billing_partner, description,
        and destination (bank name + last4). Payouts accrue slowly (a
        few per week), so default page size is #{DEFAULT_PER_PAGE}; pass
        --all with --since to bound an exhaustive scan.

        To see which individual charges landed in a payout, go through
        the charges side: each `wiq charges list` row embeds its payout,
        so filter charges by date window and group on payout.id.
      DESC
      method_option :status, type: :string,
                             desc: "Filter by status (common: #{COMMON_STATUSES.join(", ")})"
      method_option :billing_partner, type: :string, enum: BILLING_PARTNERS,
                                      desc: "Filter by billing partner (stripe | justifi)"
      method_option :since, type: :string, desc: "Earliest deposits_at (YYYY-MM-DD)"
      method_option :until, type: :string, desc: "Latest deposits_at (YYYY-MM-DD)"
      method_option :per_page, type: :numeric, default: DEFAULT_PER_PAGE,
                               desc: "Page size (default #{DEFAULT_PER_PAGE})"
      method_option :all, type: :boolean, default: false,
                          desc: "Follow pagination until exhausted"
      def list
        params = build_list_params
        records, total = fetch_index("/api/v1/payouts", params, key: "payouts")
        render_index(
          records, total: total,
          summary: "Listed #{records.size} payouts#{summary_filters_suffix}.",
          breadcrumbs: [
            { "cmd" => "wiq payouts show <id>",
              "description" => "Inspect a single payout" },
            { "cmd" => "wiq charges list --since <date> --until <date> --all",
              "description" => "Charges in a window — each row embeds its payout for reconciliation" }
          ]
        )
      end

      desc "show ID", "Fetch a single payout"
      long_desc <<~DESC
        Full payout payload: amount, currency, status, deposits_at,
        payments_count/payments_total, refunds_count/refunds_total,
        fees_total, billing_partner (+ billing_partner_id, the Stripe/
        Justifi payout id like po_...), delivery_method, description, and
        destination bank account (holder name, bank name, last4,
        account type). Money fields are integer cents.

        Auth: admin-only; a payout outside the PAT's team returns 403.
      DESC
      def show(id)
        payout = client.get("/api/v1/payouts/#{id}")
        render(payout,
               summary: "Payout #{payout["id"]} — #{payout["status"]}, " \
                        "#{format_cents(payout["amount"])} deposited #{payout["deposits_at"]}",
               breadcrumbs: [
                 { "cmd" => "wiq charges list --since <date> --until <date> --all",
                   "description" => "Find this payout's charges (rows embed payout.id)" }
               ])
      end

      no_commands do
        def build_list_params
          params = { "per_page" => options[:per_page] || DEFAULT_PER_PAGE }
          params["q[status_eq]"] = options[:status] if options[:status]
          params["q[billing_partner_eq]"] = options[:billing_partner] if options[:billing_partner]
          params["q[deposits_at_gteq]"] = options[:since] if options[:since]
          params["q[deposits_at_lteq]"] = options[:until] if options[:until]
          params
        end

        def summary_filters_suffix
          bits = []
          bits << "status=#{options[:status]}" if options[:status]
          bits << "billing_partner=#{options[:billing_partner]}" if options[:billing_partner]
          bits << "since=#{options[:since]}" if options[:since]
          bits << "until=#{options[:until]}" if options[:until]
          bits.empty? ? "" : " (#{bits.join(", ")})"
        end

        def format_cents(cents)
          return "?" unless cents.is_a?(Numeric)

          format("$%.2f", cents / 100.0)
        end
      end
    end
  end
end
