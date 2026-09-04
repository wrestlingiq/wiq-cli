# frozen_string_literal: true

RSpec.describe Wiq::Commands::ProspectFamilies do
  def attrs_for(opts = {})
    described_class.new([], opts, {}).send(:build_family_attrs)
  end

  def ids_for(raw)
    described_class.new([], {}, {}).send(:parse_id_list, raw)
  end

  describe "#build_family_attrs" do
    it "returns an empty hash when no field flags are passed" do
      expect(attrs_for).to eq({})
    end

    it "maps contact flags onto the controller's contact_* permit names" do
      attrs = attrs_for(first_name: "Dana", last_name: "Lee", email: "dana@example.com", phone: "5551234")
      expect(attrs).to eq(
        "contact_first_name" => "Dana",
        "contact_last_name" => "Lee",
        "contact_email" => "dana@example.com",
        "contact_phone" => "5551234"
      )
    end

    it "maps --assigned-coach to assigned_coach_id and guardian flags through" do
      attrs = attrs_for(assigned_coach: 3, guardian_id: 44, guardian_type: "ParentProfile")
      expect(attrs).to include("assigned_coach_id" => 3, "guardian_id" => 44, "guardian_type" => "ParentProfile")
    end
  end

  describe "#parse_id_list" do
    it "returns [] for nil or blank" do
      expect(ids_for(nil)).to eq([])
      expect(ids_for("  ")).to eq([])
    end

    it "splits on commas, strips whitespace, and drops non-numeric junk" do
      expect(ids_for("12, 34,abc,,0")).to eq([12, 34])
    end
  end

  describe "ACTIVITY_TYPES" do
    it "matches the web log-contact popover's values" do
      expect(described_class::ACTIVITY_TYPES).to eq(%w[phone_call sms email in_person other])
    end
  end

  describe "#linked_answers" do
    it "unwraps linked_profiles and counts answers across profiles" do
      cmd = described_class.new(["9"], { agent: true }, {})
      fake_client = double("client")
      allow(cmd).to receive(:client).and_return(fake_client)
      allow(cmd).to receive(:config).and_return(double(host: "https://example.test"))
      expect(fake_client).to receive(:get)
        .with("/api/v1/prospect_families/9/linked_answers")
        .and_return("linked_profiles" => [
          { "profile_id" => 1, "relation" => "guardian", "registration_answers" => [{ "id" => 1 }, { "id" => 2 }] },
          { "profile_id" => 2, "relation" => "wrestler", "registration_answers" => [] }
        ])
      expect { cmd.linked_answers("9") }.to output(/"relation":"guardian"/).to_stdout
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
