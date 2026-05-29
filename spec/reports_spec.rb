# frozen_string_literal: true

RSpec.describe Wiq::Commands::Reports do
  def version_for(opts = {})
    described_class.new([], opts, {}).send(:report_version)
  end

  describe "#report_version" do
    # vrow is the row/CSV shape behind the web Download buttons and the only
    # shape carrying RosterReport's "Added to roster at" column
    # (roster_memberships.created_at). It's also the de facto standard — most
    # reports ignore version and emit rows — so the CLI defaults to it for a
    # uniform surface. --v1 is the escape hatch to the legacy structured JSON
    # supported only by RosterReport/UsawReport/PaidSessionAccountingReport.
    it "defaults to vrow" do
      expect(version_for).to eq("vrow")
    end

    it "returns v1 when --v1 is passed" do
      expect(version_for(v1: true)).to eq("v1")
    end

    it "returns vrow when --v1 is explicitly false" do
      expect(version_for(v1: false)).to eq("vrow")
    end
  end
end
