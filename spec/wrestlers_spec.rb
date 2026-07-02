# frozen_string_literal: true

RSpec.describe Wiq::Commands::Wrestlers do
  # Bypass Thor's argv parsing — pass options directly as the hash Thor would
  # produce. This unit-tests build_list_params; Thor's enum validation and
  # option-name mapping (--first-name → :first_name) are upstream concerns
  # well-covered by Thor itself.
  def build_params_for(opts = {})
    full_opts = { profile_type: "teammate", per_page: 20 }.merge(opts)
    described_class.new([], full_opts, {}).send(:build_list_params)
  end

  describe "default behavior" do
    it "filters to teammates by default (matches WIQ web UI default)" do
      params = build_params_for
      expect(params).to include("q[profile_type_eq]" => "teammate")
    end

    it "defaults to per_page=20 (narrow surface, no --all flag exists)" do
      params = build_params_for
      expect(params["per_page"]).to eq(20)
    end

    it "omits the profile_type filter entirely when --profile-type=all" do
      params = build_params_for(profile_type: "all")
      expect(params).not_to have_key("q[profile_type_eq]")
    end
  end

  describe "option → Ransack mapping" do
    it "translates --first-name to q[first_name_cont]" do
      params = build_params_for(first_name: "Jane")
      expect(params).to include("q[first_name_cont]" => "Jane")
    end

    it "translates --last-name to q[last_name_cont]" do
      params = build_params_for(last_name: "Smith")
      expect(params).to include("q[last_name_cont]" => "Smith")
    end

    it "translates --weight-class to q[weight_class_numeric_eq]" do
      params = build_params_for(weight_class: "132")
      expect(params).to include("q[weight_class_numeric_eq]" => "132")
    end

    it "translates --academic-class to q[academic_class_eq]" do
      params = build_params_for(academic_class: "senior")
      expect(params).to include("q[academic_class_eq]" => "senior")
    end

    it "translates --age to q[age_eq]" do
      params = build_params_for(age: 14)
      expect(params).to include("q[age_eq]" => 14)
    end

    it "translates --roster to q[rosters_id_eq] (single roster; intersection deferred)" do
      params = build_params_for(roster: 42)
      expect(params).to include("q[rosters_id_eq]" => 42)
    end

    it "translates --location to the dedicated location_id param (not Ransack)" do
      params = build_params_for(location: 7)
      expect(params).to include("location_id" => 7)
    end

    it "uses the legacy ?query= for free-text name search (alongside Ransack)" do
      params = build_params_for(query: "Jane Smith")
      expect(params).to include("query" => "Jane Smith")
    end
  end

  describe "--expand parsing" do
    it "is empty by default — keeps the base payload narrow" do
      params = build_params_for
      expect(params).not_to have_key("expand_rosters")
      expect(params).not_to have_key("expand_registration_answers")
    end

    it "sets expand_rosters=true when --expand includes rosters" do
      params = build_params_for(expand: "rosters")
      expect(params["expand_rosters"]).to be true
    end

    it "sets both flags when --expand is a CSV" do
      params = build_params_for(expand: "rosters,registration_answers")
      expect(params["expand_rosters"]).to be true
      expect(params["expand_registration_answers"]).to be true
    end

    it "tolerates whitespace around CSV entries" do
      params = build_params_for(expand: "rosters, registration_answers")
      expect(params["expand_registration_answers"]).to be true
    end
  end
end
