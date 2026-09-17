# spec/syncer_spec.rb
require "syncer"
require "config"

RSpec.describe Syncer do
  let(:cfg) { Config.new(lunchmoney_token: "lm", privacy_api_key: "p", dry_run: true, days: 7, force: false) }
  let(:lm_client) { double("LM") }
  let(:priv_client) { double("Priv") }
  let(:syncer) { Syncer.new(config: cfg, lm_client: lm_client, privacy_client: priv_client) }

  it "fetches from both, matches, and does nothing in dry_run" do
    allow(lm_client).to receive(:get_transactions).and_return([])
    allow(priv_client).to receive(:list_transactions).and_return([])
    expect(lm_client).not_to receive(:update_transaction)
    syncer.run
  end

  it "fetches, matches, and calls update when not dry_run" do
    cfg = Config.new(lunchmoney_token: "lm", privacy_api_key: "p", dry_run: false, days: 7, force: false)
    lm_client = double("LM")
    priv_client = double("Priv")
    syncer = Syncer.new(config: cfg, lm_client: lm_client, privacy_client: priv_client)

    lm_tx = { "id" => 123, "date" => Date.today.iso8601, "amount" => "76.6600", "payee" => "PRIVACY*1234", "notes" => nil, "custom_metadata" => {} }
    priv_tx = {
      "token" => "764fa5a3-2371-40f0-8cbb-9a2e1230d955",
      "amount" => -7666,
      "created" => "#{Date.today.iso8601}T19:17:22Z",
      "merchant" => { "descriptor" => "RESTAURANT ABC", "city" => "NEW YORK", "state" => "NY", "mcc" => "5812" },
      "card" => { "last_four" => "6749", "memo" => "dining" }
    }

    allow(lm_client).to receive(:get_transactions).and_return([lm_tx])
    allow(priv_client).to receive(:list_transactions).and_return([priv_tx])

    expect(lm_client).to receive(:update_transaction).with(
      123,
      payee: "RESTAURANT ABC",
      custom_metadata: hash_including("privacy_transaction_token" => "764fa5a3-2371-40f0-8cbb-9a2e1230d955")
    ).and_return({ "id" => 123 })

    syncer.run
  end

  it "prints privacy-named LM tx that matched no privacy tx and does not update it even when not dry_run" do
    cfg = Config.new(lunchmoney_token: "lm", privacy_api_key: "p", dry_run: false, days: 7, force: false)
    lm_client = double("LM")
    priv_client = double("Priv")

    lm_unmatched = { "id" => 777, "date" => Date.today.iso8601, "amount" => "12.3400", "payee" => "PRIVACY*9999", "notes" => nil, "custom_metadata" => {} }
    priv_tx = { "token" => "tok", "amount" => -123456, "created" => "#{Date.today.iso8601}T19:17:22Z", "merchant" => { "descriptor" => "SOMETHING ELSE" } }

    allow(lm_client).to receive(:get_transactions).and_return([lm_unmatched])
    allow(priv_client).to receive(:list_transactions).and_return([priv_tx])

    syncer = Syncer.new(config: cfg, lm_client: lm_client, privacy_client: priv_client)

    expect(lm_client).not_to receive(:update_transaction)
    expect { syncer.run }.to output(/Unmatched privacy-named transactions \(1\):\n\s+LM#777 #{Date.today.year}-.*\$12\.3400 PRIVACY\*9999/m).to_stdout
  end

  it "does not print unmatched header when all privacy-named txs matched" do
    lm_tx = { "id" => 123, "date" => Date.today.iso8601, "amount" => "76.6600", "payee" => "PRIVACY*1234", "notes" => nil, "custom_metadata" => {} }
    priv_tx = { "token" => "tok", "amount" => -7666, "created" => "#{Date.today.iso8601}T19:17:22Z", "merchant" => { "descriptor" => "RESTAURANT ABC" } }

    allow(lm_client).to receive(:get_transactions).and_return([lm_tx])
    allow(priv_client).to receive(:list_transactions).and_return([priv_tx])

    syncer = Syncer.new(config: cfg, lm_client: lm_client, privacy_client: priv_client)

    expect { syncer.run }.not_to output(/Unmatched privacy-named transactions/).to_stdout
    expect { syncer.run }.to output(/Found 1 matches/).to_stdout
  end
end
