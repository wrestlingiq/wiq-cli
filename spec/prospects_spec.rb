# frozen_string_literal: true

RSpec.describe Wiq::Commands::Prospects do
  # Bypass Thor's argv parsing — pass options directly as the hash Thor
  # would produce and unit-test the body builder. Thor's flag-name mapping
  # (--first-name → :first_name) is covered upstream.
  def attrs_for(opts = {})
    described_class.new([], opts, {}).send(:build_prospect_attrs)
  end

  describe "#build_prospect_attrs" do
    it "returns an empty hash when no field flags are passed (PATCH stays partial)" do
      expect(attrs_for).to eq({})
    end

    it "maps child flags onto the controller's child_* permit names" do
      attrs = attrs_for(first_name: "Sam", last_name: "Lee", dob: "2016-03-04", academic_class: "4th")
      expect(attrs).to eq(
        "child_first_name" => "Sam",
        "child_last_name" => "Lee",
        "child_date_of_birth" => "2016-03-04",
        "child_academic_class" => "4th"
      )
    end

    it "maps id-style flags onto their *_id params" do
      attrs = attrs_for(paid_session: 7, trial_event: 9, wrestler_profile: 11)
      expect(attrs).to include("paid_session_id" => 7, "trial_event_id" => 9, "wrestler_profile_id" => 11)
    end

    it "passes stage and lost_reason through unchanged" do
      attrs = attrs_for(stage: "didnt_join", lost_reason: "moved away")
      expect(attrs).to include("stage" => "didnt_join", "lost_reason" => "moved away")
    end

    it "omits needs_follow_up when the boolean flag is not passed" do
      expect(attrs_for(first_name: "Sam")).not_to have_key("needs_follow_up")
    end

    it "sends needs_follow_up=false for --no-needs-follow-up (explicit false is a real value)" do
      expect(attrs_for(needs_follow_up: false)).to eq("needs_follow_up" => false)
    end

    it "sends needs_follow_up=true for --needs-follow-up" do
      expect(attrs_for(needs_follow_up: true)).to eq("needs_follow_up" => true)
    end
  end

  describe "STAGES" do
    it "matches the server's Prospect::STAGES order (forward-only rule depends on it)" do
      expect(described_class::STAGES).to eq(
        %w[inquiry trial_scheduled trialing trial_complete converted didnt_join archived]
      )
    end

    it "flags the three terminal stages" do
      expect(described_class::TERMINAL_STAGES).to eq(%w[converted didnt_join archived])
    end
  end

  describe "#advance" do
    it "rejects an unknown stage client-side before making a request" do
      cmd = described_class.new(["1", "bogus"], {}, {})
      expect { cmd.advance("1", "bogus") }.to raise_error(Wiq::Error) { |e|
        expect(e.code).to eq("invalid_stage")
        expect(e.hint).to include("trial_scheduled")
      }
    end
  end

  describe "#update" do
    it "refuses an empty update rather than sending a no-op PATCH" do
      cmd = described_class.new(["1"], {}, {})
      expect { cmd.update("1") }.to raise_error(Wiq::Error) { |e|
        expect(e.code).to eq("no_fields")
      }
    end
  end
end
