# frozen_string_literal: true

RSpec.describe Wiq::Introspection do
  let(:tree) { described_class.dump_tree }

  it "produces a stable top-level schema" do
    expect(tree.keys).to contain_exactly(
      "name", "version", "global_options", "top_level_commands", "groups"
    )
    expect(tree["name"]).to eq("wiq")
    expect(tree["version"]).to eq(Wiq::VERSION)
  end

  it "lists every command group alphabetically" do
    expect(tree["groups"].map { |g| g["name"] }).to eq(
      %w[auth billing_profiles charges check_ins doctor events locations metrics paid_sessions parents prospect_families prospects registrations reports rosters setup workflows wrestlers]
    )
  end

  it "surfaces the four global options that every command inherits" do
    expect(tree["global_options"].map { |o| o["name"] }).to contain_exactly(
      "agent", "as", "host", "json"
    )
  end

  describe "command map aliasing" do
    it "shows user-facing 'run' instead of internal 'run_report'" do
      reports = tree["groups"].find { |g| g["name"] == "reports" }
      expect(reports["commands"].map { |c| c["name"] }).to include("run")
      expect(reports["commands"].map { |c| c["name"] }).not_to include("run_report")
    end

    it "shows user-facing 'check' instead of internal 'check_all'" do
      doctor = tree["groups"].find { |g| g["name"] == "doctor" }
      expect(doctor["commands"].map { |c| c["name"] }).to eq(["check"])
    end
  end

  describe "thor-internal filtering" do
    it "drops 'help' and 'tree' from every group" do
      tree["groups"].each do |group|
        names = group["commands"].map { |c| c["name"] }
        expect(names).not_to include("help"), "group #{group["name"]} leaked 'help'"
        expect(names).not_to include("tree"), "group #{group["name"]} leaked 'tree'"
      end
    end

    it "drops subcommand placeholder entries from top_level_commands" do
      names = tree["top_level_commands"].map { |c| c["name"] }
      # All 11 subcommand groups should NOT appear as top-level commands
      %w[auth doctor check_ins reports paid_sessions metrics events rosters
         locations prospects prospect_families registrations workflows setup
         wrestlers charges billing_profiles].each do |group_name|
        expect(names).not_to include(group_name),
                               "top_level_commands leaked subcommand placeholder #{group_name}"
      end
    end

    it "keeps real top-level commands (version, commands)" do
      names = tree["top_level_commands"].map { |c| c["name"] }
      expect(names).to contain_exactly("version", "commands")
    end
  end

  describe "option metadata" do
    let(:reports_run) do
      tree["groups"]
        .find { |g| g["name"] == "reports" }["commands"]
        .find { |c| c["name"] == "run" }
    end

    it "surfaces enum values when present" do
      days = reports_run["options"].find { |o| o["name"] == "days_threshold" }
      expect(days["enum"]).to eq([7, 14, 30, 60, 90])
    end

    it "marks required options" do
      summary = tree["groups"]
        .find { |g| g["name"] == "check_ins" }["commands"]
        .find { |c| c["name"] == "summary" }
      start_opt = summary["options"].find { |o| o["name"] == "start" }
      expect(start_opt["required"]).to be true
    end

    it "omits enum when option doesn't constrain values" do
      roster = reports_run["options"].find { |o| o["name"] == "roster" }
      expect(roster).not_to have_key("enum")
    end

    it "includes type information" do
      types = reports_run["options"].map { |o| o["type"] }.uniq.sort
      expect(types).to include("numeric", "string", "boolean", "array")
    end
  end

  describe "agent-facing prose" do
    it "carries the long_description on commands that have one" do
      summary = tree["groups"]
        .find { |g| g["name"] == "prospects" }["commands"]
        .find { |c| c["name"] == "summary" }
      expect(summary["long_description"]).to match(/Single-call dashboard/)
    end

    it "preserves the original usage string (not the internal method name)" do
      run = tree["groups"]
        .find { |g| g["name"] == "reports" }["commands"]
        .find { |c| c["name"] == "run" }
      expect(run["usage"]).to eq("run TYPE")
    end
  end
end
