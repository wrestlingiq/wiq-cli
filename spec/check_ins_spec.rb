# frozen_string_literal: true

RSpec.describe Wiq::Commands::CheckIns do
  describe "CheckIn.status enum translation" do
    # CheckIn.status is an integer-backed Rails enum. Ransack 4.x does not
    # translate enum strings to integers on integer columns; sending
    # q[status_eq]=present would silently drop the predicate. The CLI
    # translates here so --status actually filters.

    it "lists exactly the 8 CheckIn.statuses values defined in the model" do
      expect(described_class::STATUSES).to eq(%w[unknown present absent excused unexcused late injured other])
    end

    it "maps each status string to its integer position in the enum" do
      expect(described_class::STATUS_TO_INT).to eq(
        "unknown" => 0,
        "present" => 1,
        "absent" => 2,
        "excused" => 3,
        "unexcused" => 4,
        "late" => 5,
        "injured" => 6,
        "other" => 7
      )
    end

    it "every status name resolves to an Integer (not a String)" do
      described_class::STATUSES.each do |s|
        expect(described_class::STATUS_TO_INT.fetch(s)).to be_a(Integer)
      end
    end
  end
end
