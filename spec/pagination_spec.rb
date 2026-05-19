# frozen_string_literal: true

RSpec.describe Wiq::Pagination do
  describe ".parse_link" do
    it "extracts a single rel=next URL" do
      header = '<https://host/api/v1/rosters?page=2>; rel="next"'
      expect(described_class.parse_link(header)).to eq("next" => "https://host/api/v1/rosters?page=2")
    end

    it "handles multiple rels separated by commas" do
      header = [
        '<https://host/api/v1/rosters?page=2>; rel="next"',
        '<https://host/api/v1/rosters?page=5>; rel="last"',
        '<https://host/api/v1/rosters?page=1>; rel="first"'
      ].join(", ")

      result = described_class.parse_link(header)
      expect(result.keys).to contain_exactly("next", "last", "first")
      expect(result["last"]).to eq("https://host/api/v1/rosters?page=5")
    end

    it "returns an empty hash for nil or empty input" do
      expect(described_class.parse_link(nil)).to eq({})
      expect(described_class.parse_link("")).to eq({})
    end
  end

  describe ".next_url" do
    it "returns the rel=next URL when present" do
      header = '<https://host/x?page=3>; rel="next", <https://host/x?page=10>; rel="last"'
      expect(described_class.next_url(header)).to eq("https://host/x?page=3")
    end

    it "returns nil when rel=next is absent" do
      header = '<https://host/x?page=10>; rel="last"'
      expect(described_class.next_url(header)).to be_nil
    end
  end

  describe ".total_count" do
    it "reads TotalCount (capitalized; matches WIQ's non-standard header name)" do
      expect(described_class.total_count("TotalCount" => "42")).to eq(42)
    end

    it "tolerates other casings" do
      expect(described_class.total_count("totalcount" => "7")).to eq(7)
    end

    it "returns nil when the header is missing or unparseable" do
      expect(described_class.total_count({})).to be_nil
      expect(described_class.total_count("TotalCount" => "not-a-number")).to be_nil
    end
  end
end
