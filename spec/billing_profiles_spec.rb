# frozen_string_literal: true

RSpec.describe Wiq::Commands::BillingProfiles do
  it "restricts profile_type to ParentProfile or CoachProfile only" do
    # WrestlerProfile is rejected server-side ("Wrestlers cannot have billing
    # profiles"). The CLI enum encodes that constraint up front.
    expect(described_class::VALID_PROFILE_TYPES).to contain_exactly(
      "ParentProfile", "CoachProfile"
    )
    expect(described_class::VALID_PROFILE_TYPES).not_to include("WrestlerProfile")
  end
end
