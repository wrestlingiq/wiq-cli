# frozen_string_literal: true

RSpec.describe Wiq::Credentials do
  let(:host) { "https://example.test" }

  describe ".store / .for_host roundtrip" do
    it "persists and retrieves a credential by host + alias" do
      described_class.store(
        host: host, alias_name: "westside", token: "wiq_pat_abc",
        token_prefix: "wiq_pat_abc", name: "Westside",
        profile: { "display_name" => "Bob", "team_name" => "Westside Wrestling", "type" => "CoachProfile" }
      )

      entry = described_class.for_host(host, "westside")
      expect(entry).to include(
        "token" => "wiq_pat_abc",
        "token_prefix" => "wiq_pat_abc",
        "name" => "Westside"
      )
      expect(entry["profile"]).to include("team_name" => "Westside Wrestling")
    end

    it "returns nil for unknown host or alias" do
      described_class.store(host: host, alias_name: "default", token: "wiq_pat_xxx")
      expect(described_class.for_host("https://other.test", "default")).to be_nil
      expect(described_class.for_host(host, "no-such-alias")).to be_nil
    end
  end

  describe ".aliases_for" do
    it "returns all aliases stored for a host" do
      described_class.store(host: host, alias_name: "default", token: "t1")
      described_class.store(host: host, alias_name: "westside", token: "t2")
      expect(described_class.aliases_for(host)).to contain_exactly("default", "westside")
    end

    it "returns an empty array for unknown hosts" do
      expect(described_class.aliases_for("https://nope.test")).to eq([])
    end
  end

  describe ".remove" do
    before do
      described_class.store(host: host, alias_name: "default", token: "t1")
      described_class.store(host: host, alias_name: "westside", token: "t2")
    end

    it "removes only the specified alias" do
      expect(described_class.remove(host, "westside")).to be true
      expect(described_class.aliases_for(host)).to eq(["default"])
    end

    it "prunes the host entry once its last alias is removed" do
      described_class.remove(host, "westside")
      described_class.remove(host, "default")
      expect(described_class.hosts).to eq([])
    end

    it "returns false when nothing was removed" do
      expect(described_class.remove("https://no.test", "default")).to be false
    end
  end

  describe "file mode" do
    it "writes credentials.json with 0600 permissions (no group/world read)" do
      described_class.store(host: host, alias_name: "default", token: "t1")
      mode = File.stat(described_class.path).mode & 0o777
      expect(mode).to eq(0o600)
    end
  end

  describe "malformed file" do
    it "returns an empty hash rather than crashing" do
      File.write(described_class.path, "not json {{")
      expect(described_class.load_all).to eq({})
    end
  end

  describe ".all_entries" do
    it "never exposes the raw token (security check)" do
      described_class.store(host: host, alias_name: "default", token: "wiq_pat_SECRET")
      entries = described_class.all_entries
      expect(entries.first).not_to have_key("token")
      expect(entries.first).to include("alias" => "default", "host" => host)
    end
  end
end
