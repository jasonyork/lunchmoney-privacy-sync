# spec/e2e_sync_spec.rb
require "syncer"
require "config"
require "lunchmoney_client"
require "privacy_client"
require "webmock/rspec"
WebMock.disable_net_connect!

RSpec.describe "end-to-end sync" do
  it "fetches, matches one tx, updates it, and reports an unmatched privacy-named tx when not dry-run" do
    cfg = Config.new(lunchmoney_token: "lm", privacy_api_key: "pk", dry_run: false, days: 30)

    lm_client = LunchMoneyClient.new(token: "lm")
    priv_client = PrivacyClient.new(api_key: "pk")

    # LM list (include_metadata true is inside client)
    stub_request(:get, /lunchmoney.dev\/v2\/transactions/)
      .to_return(body: {
        transactions: [
          { "id" => 42, "date" => "2026-06-01", "amount" => "42.0000", "payee" => "PRIVACY*1234", "notes" => nil, "custom_metadata" => {} },
          { "id" => 43, "date" => "2026-06-02", "amount" => "9.9900", "payee" => "PRIVACY*9999", "notes" => nil, "custom_metadata" => {} }
        ],
        has_more: false
      }.to_json)

    # Privacy list
    stub_request(:get, /privacy.com\/v1\/transactions/)
      .to_return(body: { data: [ { "token" => "tok-xyz", "amount" => 4200, "created" => "2026-06-01T12:00:00Z", "merchant" => { "descriptor" => "CAFE X", "city" => "SF", "state" => "CA", "mcc" => "5812" }, "card" => { "last_four" => "0001", "memo" => "test" } } ], page: 1, total_pages: 1 }.to_json)

    # The PUT we care about
    update_stub = stub_request(:put, "https://api.lunchmoney.dev/v2/transactions/42")
      .with(body: hash_including("payee" => "CAFE X", "custom_metadata" => hash_including("privacy_transaction_token" => "tok-xyz")))
      .to_return(body: { id: 42 }.to_json)

    expect { Syncer.new(config: cfg, lm_client: lm_client, privacy_client: priv_client).run }
      .to output(/Unmatched privacy-named transactions \(1\):.*LM#43 2026-06-02 \$9\.9900 PRIVACY\*9999/m).to_stdout

    expect(update_stub).to have_been_requested.once
  end
end
