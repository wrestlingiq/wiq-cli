# frozen_string_literal: true

require "stringio"

RSpec.describe Wiq::Output do
  let(:data) { [{ "id" => 1, "name" => "Varsity" }, { "id" => 2, "name" => "JV" }] }

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

  describe ".pick_mode" do
    it "honors --agent explicitly" do
      expect(described_class.pick_mode(agent: true)).to eq(:agent)
    end

    it "honors --json explicitly" do
      expect(described_class.pick_mode(json: true)).to eq(:json)
    end

    it "is :agent (bare JSON) when piped" do
      allow($stdout).to receive(:tty?).and_return(false)
      expect(described_class.pick_mode({})).to eq(:agent)
    end

    it "is :pretty on a real TTY" do
      allow($stdout).to receive(:tty?).and_return(true)
      expect(described_class.pick_mode({})).to eq(:pretty)
    end
  end

  describe ".render" do
    it "with --json emits the full envelope (ok, data, summary, meta)" do
      out = capture_stdout { described_class.render(data, summary: "Listed 2 rosters", meta: { "count" => 2 }, options: { json: true }) }
      parsed = JSON.parse(out)
      expect(parsed).to include("ok" => true, "summary" => "Listed 2 rosters")
      expect(parsed["data"]).to eq(data)
      expect(parsed["meta"]).to eq("count" => 2)
    end

    it "with --agent emits bare data, no envelope" do
      out = capture_stdout { described_class.render(data, summary: "ignored", options: { agent: true }) }
      parsed = JSON.parse(out)
      expect(parsed).to eq(data)
      expect(parsed).not_to be_a(Hash)
    end
  end

  describe ".render_error" do
    it "emits a stable error envelope with ok=false + code + hint" do
      err = Wiq::HostUnsetError.new
      stderr_io = StringIO.new
      original = $stderr
      $stderr = stderr_io
      described_class.render_error(err, options: { agent: true })
      payload = JSON.parse(stderr_io.string)
      expect(payload).to include("ok" => false, "code" => "host_unset")
      expect(payload["hint"]).to match(/wiq auth login/)
    ensure
      $stderr = original
    end
  end
end
