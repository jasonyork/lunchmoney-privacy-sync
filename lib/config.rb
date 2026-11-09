# frozen_string_literal: true

begin
  require "dotenv/load"
rescue LoadError
  # dotenv is optional; plain environment variables work without it.
end

class Config
  attr_reader :lunchmoney_token, :privacy_api_key, :privacy_base_url, :days, :dry_run

  def initialize(lunchmoney_token:, privacy_api_key:, privacy_base_url: nil, days: 14, dry_run: true)
    @lunchmoney_token = lunchmoney_token
    @privacy_api_key = privacy_api_key
    @privacy_base_url = privacy_base_url || "https://api.privacy.com/v1"
    @days = days
    @dry_run = dry_run
  end

  def self.load
    lm = ENV["LUNCHMONEY_TOKEN"]
    priv = ENV["PRIVACY_API_KEY"]
    raise "Missing required env var LUNCHMONEY_TOKEN" unless lm && !lm.empty?
    raise "Missing required env var PRIVACY_API_KEY" unless priv && !priv.empty?

    new(
      lunchmoney_token: lm,
      privacy_api_key: priv,
      privacy_base_url: ENV["PRIVACY_BASE_URL"],
      days: (ENV["SYNC_DAYS"] || 14).to_i,
      dry_run: ENV.fetch("DRY_RUN", "true") != "false"
    )
  end
end
