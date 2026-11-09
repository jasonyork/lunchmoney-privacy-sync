# spec/matcher_spec.rb
require "matcher"

RSpec.describe Matcher do
  let(:lm_tx) do
    { "id" => 123, "date" => "2026-05-15", "amount" => "76.6600", "payee" => "PRIVACY*1234", "notes" => nil, "custom_metadata" => {} }
  end
  let(:priv_tx) do
    {
      "token" => "764fa5a3-2371-40f0-8cbb-9a2e1230d955",
      "amount" => -7666, # cents, negative in this example
      "created" => "2026-05-15T19:17:22Z",
      "merchant" => { "descriptor" => "RESTAURANT ABC", "city" => "NEW YORK", "state" => "NY", "mcc" => "5812" },
      "card" => { "last_four" => "6749", "memo" => "dining" }
    }
  end

  it "matches on absolute amount (cents vs dollars) and same date" do
    matches = Matcher.match(lm_transactions: [lm_tx], privacy_transactions: [priv_tx])
    expect(matches.size).to eq(1)
    expect(matches.first[:lm_id]).to eq(123)
    expect(matches.first[:privacy_token]).to eq("764fa5a3-2371-40f0-8cbb-9a2e1230d955")
    expect(matches.first[:suggested_payee]).to eq("RESTAURANT ABC")
  end

  it "skips LM tx that already has privacy_transaction_token in custom_metadata" do
    lm_enriched = lm_tx.merge("custom_metadata" => { "privacy_transaction_token" => "already" })
    matches = Matcher.match(lm_transactions: [lm_enriched], privacy_transactions: [priv_tx])
    expect(matches).to be_empty
  end

  it "tolerates 2-day date window and different signs" do
    lm_off = lm_tx.merge("date" => "2026-05-17", "amount" => "-76.6600")
    matches = Matcher.match(lm_transactions: [lm_off], privacy_transactions: [priv_tx])
    expect(matches.size).to eq(1)
  end

  it "does not match when absolute amount delta > 0.01" do
    lm_off_amt = lm_tx.merge("amount" => "76.68")
    matches = Matcher.match(lm_transactions: [lm_off_amt], privacy_transactions: [priv_tx])
    expect(matches).to be_empty
  end

  it "skips LM tx whose payee does not contain 'Privacy'" do
    lm_nonpriv = lm_tx.merge("payee" => "AMAZON PRIME")
    matches = Matcher.match(lm_transactions: [lm_nonpriv], privacy_transactions: [priv_tx])
    expect(matches).to be_empty
  end

  it "skips already-enriched LM tx (extra explicit case from Step 4)" do
    lm_enriched2 = { "id" => 999, "date" => "2026-05-15", "amount" => "10.00", "custom_metadata" => { "privacy_transaction_token" => "foo-bar" } }
    matches = Matcher.match(lm_transactions: [lm_enriched2], privacy_transactions: [priv_tx])
    expect(matches).to be_empty
  end

  it "does not match a refund privacy tx (RETURN event)" do
    priv_refund = priv_tx.merge("events" => [{ "type" => "RETURN", "amount" => 7666 }])
    matches = Matcher.match(lm_transactions: [lm_tx], privacy_transactions: [priv_refund])
    expect(matches).to be_empty
  end

  it "does not match a credit privacy tx (CREDIT_AUTHORIZATION event)" do
    priv_credit = priv_tx.merge("events" => [{ "type" => "CREDIT_AUTHORIZATION", "amount" => 7666 }])
    matches = Matcher.match(lm_transactions: [lm_tx], privacy_transactions: [priv_credit])
    expect(matches).to be_empty
  end

  it "matches a negative-amount privacy tx with only purchase events (amount sign is not the discriminator)" do
    priv_purchase = priv_tx.merge("events" => [{ "type" => "AUTHORIZATION", "amount" => 7666 }, { "type" => "CLEARING", "amount" => 7666 }])
    matches = Matcher.match(lm_transactions: [lm_tx], privacy_transactions: [priv_purchase])
    expect(matches.size).to eq(1)
  end

  it "never matches the same LM tx to more than one privacy tx" do
    lm_a = lm_tx.merge("id" => 1, "date" => "2026-05-15")
    lm_b = lm_tx.merge("id" => 2, "date" => "2026-05-16")
    priv_a = priv_tx.merge("token" => "a", "created" => "2026-05-15T10:00:00Z")
    priv_b = priv_tx.merge("token" => "b", "created" => "2026-05-16T10:00:00Z")
    matches = Matcher.match(lm_transactions: [lm_a, lm_b], privacy_transactions: [priv_a, priv_b])
    expect(matches.map { |m| [m[:lm_id], m[:privacy_token]] }).to contain_exactly([1, "a"], [2, "b"])
  end

  describe ".unmatched" do
    it "returns privacy-named, non-enriched, non-matched LM tx" do
      unmatched_tx = { "id" => 555, "date" => "2026-05-14", "amount" => "10.00", "payee" => "PRIVACY*9999", "custom_metadata" => {} }
      result = Matcher.unmatched(lm_transactions: [unmatched_tx], matched_ids: [])
      expect(result.map { |t| t["id"] }).to eq([555])
    end

    it "excludes a non-privacy payee" do
      result = Matcher.unmatched(lm_transactions: [lm_tx.merge("payee" => "AMAZON PRIME")], matched_ids: [])
      expect(result).to be_empty
    end

    it "excludes an already-enriched tx" do
      enriched = lm_tx.merge("custom_metadata" => { "privacy_transaction_token" => "already" })
      result = Matcher.unmatched(lm_transactions: [enriched], matched_ids: [])
      expect(result).to be_empty
    end

    it "excludes a tx whose id appears in matched_ids" do
      matched_ids = [lm_tx["id"]]
      result = Matcher.unmatched(lm_transactions: [lm_tx], matched_ids: matched_ids)
      expect(result).to be_empty
    end
  end
end
