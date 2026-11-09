# frozen_string_literal: true
require "faraday"
require "faraday/retry"
require "json"

class PrivacyClient
  def initialize(api_key:, base_url: "https://api.privacy.com/v1")
    @api_key = api_key
    @conn = Faraday.new(url: base_url) do |f|
      f.request :retry, max: 2, interval: 0.5, backoff_factor: 2
      f.adapter Faraday.default_adapter
    end
  end

  # Returns flat array of transaction hashes (all pages)
  # Accepts `begin:` / `end:` (YYYY-MM-DD). Those are Ruby keywords, so they
  # arrive via **range instead of named parameters.
  def list_transactions(result: "APPROVED", page_size: 50, **range)
    all = []
    page = 1
    loop do
      resp = @conn.get("transactions", {
        begin: range[:begin],
        end: range[:end],
        result: result,
        page: page,
        page_size: page_size
      }.compact, { "Authorization" => "api-key #{@api_key}" })

      handle_errors(resp)

      body = JSON.parse(resp.body)
      data = body.fetch("data", [])
      all.concat(data)
      break if page >= body.fetch("total_pages", 1)
      page += 1
    end
    all
  end

  private

  def handle_errors(resp)
    return if resp.success?
    raise "Privacy API error #{resp.status}: #{resp.body}"
  end
end
