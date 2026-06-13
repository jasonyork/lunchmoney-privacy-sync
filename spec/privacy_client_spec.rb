# spec/privacy_client_spec.rb
require "privacy_client"
require "webmock/rspec"
WebMock.disable_net_connect!

RSpec.describe PrivacyClient do
  let(:api_key) { "priv_test" }
  let(:client) { PrivacyClient.new(api_key: api_key, base_url: "https://sandbox.privacy.com/v1") }

  it "lists transactions with correct auth header and pagination params" do
    stub = stub_request(:get, "https://sandbox.privacy.com/transactions")
      .with(
        headers: { "Authorization" => "api-key priv_test" },
        query: hash_including("begin" => "2026-05-01", "end" => "2026-05-31", "page" => "1", "page_size" => "50", "result" => "APPROVED")
      )
      .to_return(
        status: 200,
        body: {
          data: [
            {
              "token" => "764fa5a3-2371-40f0-8cbb-9a2e1230d955",
              "amount" => -7666,
              "created" => "2026-05-15T19:17:22Z",
              "status" => "SETTLING",
              "result" => "APPROVED",
              "merchant" => {
                "descriptor" => "RESTAURANT ABC",
                "city" => "NEW YORK",
                "state" => "NY",
                "country" => "USA",
                "mcc" => "5812"
              },
              "card" => {
                "token" => "079d1898-65f7-4d66-b0bc-172d2935a5fa",
                "last_four" => "6749",
                "memo" => "dining card"
              }
            }
          ],
          page: 1,
          total_entries: 1,
          total_pages: 1
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    txs = client.list_transactions(begin: "2026-05-01", end: "2026-05-31", result: "APPROVED")
    expect(txs.size).to eq(1)
    expect(txs.first["merchant"]["descriptor"]).to eq("RESTAURANT ABC")
    expect(WebMock).to have_requested(:get, /transactions/).with(headers: { "Authorization" => "api-key priv_test" })
  end
end
