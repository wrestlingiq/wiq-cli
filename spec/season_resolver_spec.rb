# frozen_string_literal: true

RSpec.describe Wiq::SeasonResolver do
  describe "#filter_rosters_by_ids" do
    let(:rosters) do
      [
        { "id" => 1, "name" => "Varsity",  "roster_syncers" => [{ "paid_session_id" => 100 }] },
        { "id" => 2, "name" => "JV",       "roster_syncers" => [{ "paid_session_id" => 200 }] },
        { "id" => 3, "name" => "Alumni",   "roster_syncers" => [] },
        { "id" => 4, "name" => "Mixed",    "roster_syncers" => [{ "paid_session_id" => 100 }, { "paid_session_id" => 999 }] }
      ]
    end

    it "keeps rosters whose syncers include any of the given paid_session_ids" do
      resolver = described_class.new(:unused_client)
      kept = resolver.filter_rosters_by_ids(rosters, [100])
      expect(kept.map { |r| r["id"] }).to contain_exactly(1, 4)
    end

    it "drops rosters with no matching syncers (including syncerless rosters)" do
      resolver = described_class.new(:unused_client)
      kept = resolver.filter_rosters_by_ids(rosters, [200])
      expect(kept.map { |r| r["id"] }).to eq([2])
    end

    it "returns an empty list when no roster matches" do
      resolver = described_class.new(:unused_client)
      kept = resolver.filter_rosters_by_ids(rosters, [42_424_242])
      expect(kept).to be_empty
    end
  end

  describe "#paid_sessions_for" do
    it "calls the API with the right Ransack overlap params for the year" do
      client = instance_double(Wiq::Client)
      observed_params = nil
      allow(client).to receive(:collect_all) do |_path, params, **|
        observed_params = params
        [[{ "id" => 7 }], 1]
      end

      sessions = described_class.new(client).paid_sessions_for(2026)
      expect(sessions).to eq([{ "id" => 7 }])
      expect(observed_params).to include(
        "q[start_at_lteq]" => "2026-12-31",
        "q[end_at_gteq]" => "2026-01-01"
      )
    end
  end
end
