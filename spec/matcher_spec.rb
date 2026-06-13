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

  it "skips already-enriched LM tx (extra explicit case from Step 4)" do
    lm_enriched2 = { "id" => 999, "date" => "2026-05-15", "amount" => "10.00", "custom_metadata" => { "privacy_transaction_token" => "foo-bar" } }
    matches = Matcher.match(lm_transactions: [lm_enriched2], privacy_transactions: [priv_tx])
    expect(matches).to be_empty
  end
end
