require "config"
require "dotenv/load"

RSpec.describe Config do
  it "loads tokens from ENV" do
    stub_const("ENV", ENV.to_h.merge(
      "LUNCHMONEY_TOKEN" => "lm_test_123",
      "PRIVACY_API_KEY" => "priv_test_456"
    ))
    cfg = Config.load
    expect(cfg.lunchmoney_token).to eq("lm_test_123")
    expect(cfg.privacy_api_key).to eq("priv_test_456")
  end

  it "raises helpful error when tokens missing" do
    stub_const("ENV", {})
    expect { Config.load }.to raise_error(/LUNCHMONEY_TOKEN/)
  end

  it "defaults to dry run and honors DRY_RUN=false" do
    base = { "LUNCHMONEY_TOKEN" => "lm", "PRIVACY_API_KEY" => "pk" }
    stub_const("ENV", base)
    expect(Config.load.dry_run).to be(true)
    stub_const("ENV", base.merge("DRY_RUN" => "false"))
    expect(Config.load.dry_run).to be(false)
  end
end
