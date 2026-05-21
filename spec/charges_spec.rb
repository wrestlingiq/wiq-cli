# frozen_string_literal: true

RSpec.describe Wiq::Commands::Charges do
  def build_params_for(opts = {})
    full_opts = { per_page: 50 }.merge(opts)
    described_class.new([], full_opts, {}).send(:build_list_params)
  end

  describe "option → Ransack mapping" do
    it "translates --status to q[status_eq]" do
      expect(build_params_for(status: "failed")).to include("q[status_eq]" => "failed")
    end

    it "translates --billing-profile to q[billing_profile_id_eq]" do
      expect(build_params_for(billing_profile: 42)).to include("q[billing_profile_id_eq]" => 42)
    end

    it "translates --chargeable-type to q[chargeable_type_eq]" do
      params = build_params_for(chargeable_type: "BillingSubscriptionInvoice")
      expect(params).to include("q[chargeable_type_eq]" => "BillingSubscriptionInvoice")
    end

    it "translates --since to q[created_at_gteq]" do
      expect(build_params_for(since: "2026-04-01")).to include("q[created_at_gteq]" => "2026-04-01")
    end

    it "translates --until to q[created_at_lteq]" do
      expect(build_params_for(until: "2026-05-01")).to include("q[created_at_lteq]" => "2026-05-01")
    end
  end

  describe "defaults" do
    it "defaults to per_page=50 (charges accumulate fast)" do
      expect(build_params_for["per_page"]).to eq(50)
    end

    it "applies no Ransack filters when no options are passed" do
      params = build_params_for
      expect(params.keys).to eq(["per_page"])
    end
  end

  describe "status enum surface" do
    it "lists exactly the two values Charge.statuses defines" do
      expect(described_class::STATUSES).to eq(%w[successful failed])
    end
  end
end
