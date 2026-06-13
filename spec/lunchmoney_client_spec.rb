# spec/lunchmoney_client_spec.rb
require "lunchmoney_client"
require "webmock/rspec"
WebMock.disable_net_connect!

RSpec.describe LunchMoneyClient do
  let(:token) { "lm_test" }
  let(:client) { LunchMoneyClient.new(token: token) }

  it "fetches transactions with include_metadata=true and date filters" do
    stub_request(:get, "https://api.lunchmoney.dev/transactions")
      .with(
        headers: { "Authorization" => "Bearer lm_test" },
        query: hash_including("start_date" => "2026-05-01", "end_date" => "2026-05-31", "limit" => "2000", "include_metadata" => "true")
      )
      .to_return(
        status: 200,
        body: {
          transactions: [
            {
              "id" => 2112150655,
              "date" => "2026-05-28",
              "amount" => "12.3400",
              "currency" => "usd",
              "payee" => "PRIVACY*1234",
              "notes" => nil,
              "original_name" => "PRIVACY.COM",
              "is_pending" => false,
              "custom_metadata" => {}
            }
          ],
          has_more: false
        }.to_json
      )

    txs = client.get_transactions(start_date: "2026-05-01", end_date: "2026-05-31")
    expect(txs.first["payee"]).to eq("PRIVACY*1234")
    expect(txs.first["amount"]).to eq("12.3400")
  end

  it "updates a transaction payee (from privacy merchant.descriptor) and custom_metadata via PUT" do
    stub = stub_request(:put, "https://api.lunchmoney.dev/transactions/2112150655")
      .with(
        headers: { "Authorization" => "Bearer lm_test", "Content-Type" => "application/json" },
        body: hash_including("payee" => "RESTAURANT ABC", "custom_metadata" => { "privacy_transaction_token" => "764fa5a3-..." })
      )
      .to_return(status: 200, body: { id: 2112150655 }.to_json)

    result = client.update_transaction(2112150655, payee: "RESTAURANT ABC", custom_metadata: { "privacy_transaction_token" => "764fa5a3-..." })
    expect(result["id"]).to eq(2112150655)
  end
end
