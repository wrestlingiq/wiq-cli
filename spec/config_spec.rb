# frozen_string_literal: true

RSpec.describe Wiq::Config do
  let(:host_a) { "https://example.test" }
  let(:host_b) { "https://qa.example.test" }

  describe "host resolution" do
    it "falls back to the production default when nothing else is set" do
      cfg = described_class.load
      expect(cfg.host).to eq(Wiq::Config::PRODUCTION_HOST)
      expect(cfg.sources[:host]).to eq("production default")
    end

    it "honors WIQ_HOST over the production default" do
      ENV["WIQ_HOST"] = host_a
      cfg = described_class.load
      expect(cfg.host).to eq(host_a)
      expect(cfg.sources[:host]).to eq("WIQ_HOST env")
    end

    it "lets --host beat WIQ_HOST" do
      ENV["WIQ_HOST"] = host_a
      cfg = described_class.load(host: host_b)
      expect(cfg.host).to eq(host_b)
      expect(cfg.sources[:host]).to eq("--host flag")
    end

    it "uses the sole stored host when no flag/env is set" do
      Wiq::Credentials.store(host: host_a, alias_name: "default", token: "t")
      cfg = described_class.load
      expect(cfg.host).to eq(host_a)
      expect(cfg.sources[:host]).to eq("credentials store (sole host)")
    end
  end

  describe "alias resolution" do
    before { Wiq::Credentials.store(host: host_a, alias_name: "default", token: "t1") }

    it "picks 'default' when present in a multi-alias bucket" do
      Wiq::Credentials.store(host: host_a, alias_name: "westside", token: "t2")
      cfg = described_class.load(host: host_a)
      expect(cfg.alias_name).to eq("default")
      expect(cfg.sources[:alias]).to eq("credentials store (default)")
    end

    it "picks the sole alias even when not named 'default'" do
      ENV["WIQ_CREDENTIALS_PATH"] = ENV["WIQ_CREDENTIALS_PATH"]
      Wiq::Credentials.remove(host_a, "default")
      Wiq::Credentials.store(host: host_a, alias_name: "westside", token: "t2")
      cfg = described_class.load(host: host_a)
      expect(cfg.alias_name).to eq("westside")
      expect(cfg.sources[:alias]).to eq("credentials store (sole alias)")
    end

    it "leaves alias unresolved when multiple aliases exist and none is 'default'" do
      Wiq::Credentials.remove(host_a, "default")
      Wiq::Credentials.store(host: host_a, alias_name: "club-a", token: "t1")
      Wiq::Credentials.store(host: host_a, alias_name: "club-b", token: "t2")
      cfg = described_class.load(host: host_a)
      expect(cfg.alias_name).to be_nil
      expect(cfg.sources[:alias]).to match(/ambiguous/)
    end

    it "honors --as over the store" do
      Wiq::Credentials.store(host: host_a, alias_name: "westside", token: "t2")
      cfg = described_class.load(host: host_a, as: "westside")
      expect(cfg.alias_name).to eq("westside")
      expect(cfg.sources[:alias]).to eq("--as flag")
    end

    it "honors WIQ_ALIAS over the store but below --as" do
      Wiq::Credentials.store(host: host_a, alias_name: "westside", token: "t2")
      ENV["WIQ_ALIAS"] = "westside"
      cfg = described_class.load(host: host_a)
      expect(cfg.alias_name).to eq("westside")
      expect(cfg.sources[:alias]).to eq("WIQ_ALIAS env")
    end
  end

  describe "token resolution" do
    it "loads the token for the resolved (host, alias) slot" do
      Wiq::Credentials.store(host: host_a, alias_name: "default", token: "wiq_pat_abc")
      cfg = described_class.load(host: host_a)
      expect(cfg.token).to eq("wiq_pat_abc")
      expect(cfg.sources[:token]).to eq("credentials store (alias=default)")
    end

    it "lets WIQ_TOKEN override the stored entry entirely" do
      Wiq::Credentials.store(host: host_a, alias_name: "default", token: "wiq_pat_stored")
      ENV["WIQ_TOKEN"] = "wiq_pat_override"
      cfg = described_class.load(host: host_a)
      expect(cfg.token).to eq("wiq_pat_override")
      expect(cfg.sources[:token]).to eq("WIQ_TOKEN env")
    end
  end

  describe "#require_token!" do
    it "raises NotAuthenticatedError when no creds exist for the host" do
      cfg = described_class.load(host: host_a)
      expect { cfg.require_token! }.to raise_error(Wiq::NotAuthenticatedError)
    end

    it "raises AmbiguousAliasError when multiple non-default aliases are stored" do
      Wiq::Credentials.store(host: host_a, alias_name: "club-a", token: "t1")
      Wiq::Credentials.store(host: host_a, alias_name: "club-b", token: "t2")
      cfg = described_class.load(host: host_a)
      expect { cfg.require_token! }.to raise_error(Wiq::AmbiguousAliasError)
    end

    it "raises AliasNotFoundError when --as names a slot that doesn't exist" do
      Wiq::Credentials.store(host: host_a, alias_name: "default", token: "t1")
      cfg = described_class.load(host: host_a, as: "nope")
      expect { cfg.require_token! }.to raise_error(Wiq::AliasNotFoundError)
    end

    it "passes silently when host + alias + token all resolve" do
      Wiq::Credentials.store(host: host_a, alias_name: "default", token: "t1")
      cfg = described_class.load(host: host_a)
      expect { cfg.require_token! }.not_to raise_error
    end
  end
end
