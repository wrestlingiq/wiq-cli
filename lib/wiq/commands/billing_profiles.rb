# frozen_string_literal: true

module Wiq
  module Commands
    class BillingProfiles < Base
      VALID_PROFILE_TYPES = %w[ParentProfile CoachProfile].freeze

      desc "show PROFILE_ID", "Look up a parent or coach's billing profile"
      long_desc <<~DESC
        Fetches the billing profile (payment-method metadata + Stripe/Justifi
        linkage) for a specific parent or coach profile.

        Path: GET /api/v1/billing_profiles/<profile_type>/<profile_id>.

        WrestlerProfile is not supported — wrestlers themselves don't have
        billing profiles in WIQ. To find which family paid for a given
        wrestler, walk via `wiq wrestlers show <id>` to find the parents
        array, then call this for one of the parent profile ids.

        Returns: id, email, billing_partner (stripe | justifi),
        default_payment_method_{last4, brand, exp_month, exp_year}, and
        the embedded billable profile (full_name, type).

        Pass --for-update to get a setup_intent for card-on-file updates;
        not relevant for read-only agent flows.
      DESC
      method_option :profile_type, type: :string, required: true,
                                   enum: VALID_PROFILE_TYPES,
                                   desc: "ParentProfile | CoachProfile (WrestlerProfile not supported)"
      method_option :for_update, type: :boolean, default: false,
                                 desc: "Include setup_intent + billing_partner_key for card updates"
      def show(profile_id)
        params = {}
        params["for_update"] = true if options[:for_update]

        billing_profile = client.get(
          "/api/v1/billing_profiles/#{options[:profile_type]}/#{profile_id}",
          params
        )
        render(billing_profile,
               summary: "Billing profile #{billing_profile["id"]} for " \
                        "#{options[:profile_type]} #{profile_id}.",
               breadcrumbs: [
                 { "cmd" => "wiq charges list --billing-profile #{billing_profile["id"]}",
                   "description" => "Payment history for this family" },
                 { "cmd" => "wiq charges list --billing-profile #{billing_profile["id"]} --status failed --since <date>",
                   "description" => "Recent failed charges" }
               ])
      end
    end
  end
end
