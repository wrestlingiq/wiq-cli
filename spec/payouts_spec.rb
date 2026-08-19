# frozen_string_literal: true

RSpec.describe Wiq::Commands::Payouts do
  def build_params_for(opts = {})
    full_opts = { per_page: 25 }.merge(opts)
    described_class.new([], full_opts, {}).send(:build_list_params)
  end

  describe "option → Ransack mapping" do
    # Payout.status is a plain text column (not an integer-backed enum
    # like Charge.status), so the string passes through untranslated.
    it "passes --status through as q[status_eq] string" do
      expect(build_params_for(status: "paid")).to include("q[status_eq]" => "paid")
    end

    it "translates --billing-partner to q[billing_partner_eq]" do
      expect(build_params_for(billing_partner: "justifi")).to include("q[billing_partner_eq]" => "justifi")
    end

    # deposits_at, not created_at — the window a treasurer reconciling a
    # bank statement cares about is when the money landed.
    it "translates --since to q[deposits_at_gteq]" do
      expect(build_params_for(since: "2026-07-01")).to include("q[deposits_at_gteq]" => "2026-07-01")
    end

    it "translates --until to q[deposits_at_lteq]" do
      expect(build_params_for(until: "2026-08-01")).to include("q[deposits_at_lteq]" => "2026-08-01")
    end
  end

  describe "defaults" do
    it "defaults to per_page=25 (payouts accrue slowly)" do
      expect(build_params_for["per_page"]).to eq(25)
    end

    it "applies no Ransack filters when no options are passed" do
      params = build_params_for
      expect(params.keys).to eq(["per_page"])
    end
  end

  describe "#format_cents" do
    let(:command) { described_class.new([], {}, {}) }

    it "formats integer cents as dollars" do
      expect(command.send(:format_cents, 123_456)).to eq("$1234.56")
    end

    it "degrades to ? for a missing amount" do
      expect(command.send(:format_cents, nil)).to eq("?")
    end
  end
end
