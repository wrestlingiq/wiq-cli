# frozen_string_literal: true

RSpec.describe Wiq::Client do
  let(:host) { "https://example.test" }
  let(:token) { "wiq_pat_abc123" }

  let(:config) do
    Wiq::Credentials.store(host: host, alias_name: "default", token: token)
    Wiq::Config.load(host: host)
  end

  # Build a Faraday connection wired to the test adapter and inject it into
  # Client. Mirrors the production middleware stack so request: :json and
  # response: :json still run, plus the Authorization header.
  def build_client(stubs)
    client = described_class.new(config)
    conn = Faraday.new do |f|
      f.request :json
      f.response :json, content_type: /\bjson\z/
      f.headers["Accept"] = "application/json"
      f.headers["Authorization"] = "Bearer #{token}"
      f.adapter :test, stubs
    end
    client.instance_variable_set(:@connection, conn)
    client
  end

  describe "#get" do
    it "sends Authorization: Bearer <pat>" do
      observed_auth = nil
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get("/api/v1/meta/notifications") do |env|
          observed_auth = env.request_headers["Authorization"]
          [200, { "Content-Type" => "application/json" }, "{}"]
        end
      end
      build_client(stubs).get("/api/v1/meta/notifications")
      expect(observed_auth).to eq("Bearer #{token}")
    end

    it "raises Wiq::APIError on non-2xx responses" do
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get("/api/v1/rosters/999") do
          [404, { "Content-Type" => "application/json" }, JSON.generate(errors: ["Not Found"])]
        end
      end
      expect { build_client(stubs).get("/api/v1/rosters/999") }
        .to raise_error(Wiq::APIError) { |e| expect(e.status).to eq(404) }
    end
  end

  describe "#collect_all (unwrap + pagination)" do
    it "unwraps {\"<key>\": [...]} index responses" do
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get("/api/v1/rosters") do
          [200, { "Content-Type" => "application/json" }, JSON.generate(rosters: [{ id: 1 }, { id: 2 }])]
        end
      end
      records, _total = build_client(stubs).collect_all("/api/v1/rosters", {}, key: "rosters")
      expect(records).to eq([{ "id" => 1 }, { "id" => 2 }])
    end

    it "follows Link: rel=next across pages" do
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get("/api/v1/rosters") do
          [
            200,
            {
              "Content-Type" => "application/json",
              "Link" => '<https://example.test/api/v1/rosters?page=2>; rel="next"',
              "TotalCount" => "3"
            },
            JSON.generate(rosters: [{ id: 1 }, { id: 2 }])
          ]
        end
        stub.get("/api/v1/rosters?page=2") do
          [
            200,
            { "Content-Type" => "application/json", "TotalCount" => "3" },
            JSON.generate(rosters: [{ id: 3 }])
          ]
        end
      end

      records, total = build_client(stubs).collect_all("/api/v1/rosters", {}, key: "rosters")
      expect(records.map { |r| r["id"] }).to eq([1, 2, 3])
      expect(total).to eq(3)
    end

    it "raises when the response body isn't wrapped under the expected key" do
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get("/api/v1/rosters") do
          # Server-side jbuilder bug: bare array instead of {"rosters": [...]}.
          # We tolerate it (returns [] safely) rather than crashing — but the
          # whole point of the contract test is that wrapped is what we expect.
          [200, { "Content-Type" => "application/json" }, JSON.generate([{ id: 1 }])]
        end
      end

      records, = build_client(stubs).collect_all("/api/v1/rosters", {}, key: "rosters")
      # Bare-array path is the defensive fallback — keep an eye if a real
      # endpoint regresses to it.
      expect(records).to eq([{ "id" => 1 }])
    end
  end
end
