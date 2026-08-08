# frozen_string_literal: true

RSpec.describe Wiq::Commands::Parents do
  # Bypass Thor's argv parsing — pass options directly as the hash Thor would
  # produce. This unit-tests build_list_params; Thor's option-name mapping
  # (--first-name → :first_name) is an upstream concern covered by Thor itself.
  def build_params_for(opts = {})
    full_opts = { per_page: 20 }.merge(opts)
    described_class.new([], full_opts, {}).send(:build_list_params)
  end

  describe "default behavior" do
    it "defaults to per_page=20 (narrow surface, no --all flag exists)" do
      params = build_params_for
      expect(params["per_page"]).to eq(20)
    end

    it "sends no filters or expands by default" do
      params = build_params_for
      expect(params.keys).to eq(["per_page"])
    end
  end

  describe "option → query-param mapping" do
    it "uses the legacy ?query= for free-text name search" do
      params = build_params_for(query: "Jane Smith")
      expect(params).to include("query" => "Jane Smith")
    end

    it "translates --first-name to q[first_name_cont]" do
      params = build_params_for(first_name: "Jane")
      expect(params).to include("q[first_name_cont]" => "Jane")
    end

    it "translates --last-name to q[last_name_cont]" do
      params = build_params_for(last_name: "Smith")
      expect(params).to include("q[last_name_cont]" => "Smith")
    end
  end

  describe "--expand parsing" do
    it "sets expand_notification_preferences=true when --expand includes notification_preferences" do
      params = build_params_for(expand: "notification_preferences")
      expect(params["expand_notification_preferences"]).to be true
    end

    it "ignores unknown expand values rather than sending them" do
      params = build_params_for(expand: "rosters")
      expect(params.keys).to eq(["per_page"])
    end
  end
end
