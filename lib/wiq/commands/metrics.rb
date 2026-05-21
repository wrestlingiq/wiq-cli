# frozen_string_literal: true

module Wiq
  module Commands
    class Metrics < Base
      NAMES = %w[
        active_subscribers
        cancelled_subscriptions
        category_breakdown_net
        charge_avg
        charge_count
        gross_volume
        mrr
        net_volume
        new_subscriptions
        renewed_subscriptions
        revenue_per_subscriber
      ].freeze

      CURRENCY_METRICS = %w[
        gross_volume net_volume mrr charge_avg revenue_per_subscriber
        category_breakdown_net
      ].freeze

      VALID_RANGES = ["today", "7d", "4w", "3m", "12m", "year to date", "custom"].freeze
      VALID_INTERVALS = %w[hourly daily weekly monthly].freeze

      desc "list", "Print the supported metric names"
      long_desc <<~DESC
        Static enumeration of the dashboard metrics WIQ exposes at
        /api/v1/metrics/<name>. The `currency` flag tells you whether
        values are integer cents (true) or counts (false).

        Auth: every metric requires `authorize :finances, :show?`, which
        in practice means admin-coach. Non-admin PATs return 403.
      DESC
      def list
        rows = NAMES.map do |n|
          { "name" => n, "currency" => CURRENCY_METRICS.include?(n) }
        end
        render_index(rows,
                     summary: "Use `wiq metrics show <name>` to fetch a specific metric. " \
                              "Currency values are returned in integer cents.",
                     breadcrumbs: [
                       { "cmd" => "wiq metrics show mrr", "description" => "Example: monthly recurring revenue" }
                     ])
      end

      desc "show NAME", "Fetch a single dashboard metric"
      long_desc <<~DESC
        Pulls /api/v1/metrics/<name> with the standard range/interval
        params. The server returns both a primary_series and a
        comparison_series (the previous period of the same length), plus
        primary_total and comparison_total. The CLI drops the
        server-rendered `charts[]` blob entirely — it's HTML for
        Highcharts and not useful headless.

        Ranges: today, 7d, 4w, 3m, 12m, "year to date", custom.
        With --range custom you must pass --start-date and --end-date
        (YYYY-MM-DD); comparison_series will be empty for custom ranges.

        Intervals: hourly, daily, weekly, monthly. Invalid values are
        silently coerced to `daily` server-side.

        Currency metrics return integer cents (divide by 100 for dollars).
        Non-currency metrics return raw counts.
      DESC
      method_option :range, type: :string, default: "7d", desc: VALID_RANGES.join(" | ")
      method_option :interval, type: :string, default: "daily",
                               enum: VALID_INTERVALS, desc: "interval_group"
      method_option :start_date, type: :string, desc: "Required if --range=custom"
      method_option :end_date, type: :string, desc: "Required if --range=custom"
      method_option :no_comparison, type: :boolean, default: false,
                                    desc: "Drop comparison_series/comparison_total from output"
      def show(name)
        unless VALID_RANGES.include?(options[:range])
          raise Wiq::Error.new("Invalid --range #{options[:range].inspect}",
                               code: "invalid_range",
                               hint: "Valid: #{VALID_RANGES.join(", ")}")
        end

        params = {
          "range" => options[:range],
          "interval_group" => options[:interval]
        }
        if options[:range] == "custom"
          unless options[:start_date] && options[:end_date]
            raise Wiq::Error.new("--start-date and --end-date are required when --range=custom.",
                                 code: "missing_custom_dates")
          end
          params["start_date"] = options[:start_date]
          params["end_date"] = options[:end_date]
        end

        payload = client.get("/api/v1/metrics/#{name}", params)
        metrics = payload["metrics"] || {}

        data = {
          "name" => name,
          "currency" => CURRENCY_METRICS.include?(name),
          "primary_series" => metrics["primary_series"],
          "primary_total" => metrics["primary_total"]
        }
        unless options[:no_comparison]
          data["comparison_series"] = metrics["comparison_series"]
          data["comparison_total"] = metrics["comparison_total"]
        end

        render(data,
               summary: "metric=#{name} range=#{options[:range]} interval=#{options[:interval]}",
               meta: { "currency_unit" => CURRENCY_METRICS.include?(name) ? "cents" : "count" },
               breadcrumbs: [
                 { "cmd" => "wiq metrics list", "description" => "See all supported metrics" }
               ])
      end
    end
  end
end
