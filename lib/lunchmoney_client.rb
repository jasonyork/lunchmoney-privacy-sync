# frozen_string_literal: true
require "faraday"
require "faraday/retry"
require "json"

class LunchMoneyClient
  BASE = "https://api.lunchmoney.dev/v2"

  def initialize(token:)
    @token = token
    @conn = Faraday.new(url: BASE) do |f|
      f.request :retry, max: 2, interval: 1, backoff_factor: 2
      f.adapter Faraday.default_adapter
    end
  end

  def get_transactions(start_date: nil, end_date: nil, limit: 2000)
    resp = @conn.get("transactions", {
      start_date: start_date,
      end_date: end_date,
      limit: limit,
      include_metadata: true
    }.compact, auth_header)

    handle_errors(resp)
    JSON.parse(resp.body).fetch("transactions", [])
  end

  def update_transaction(id, payee: nil, custom_metadata: nil)
    body = {}
    body["payee"] = payee if payee
    body["custom_metadata"] = custom_metadata if custom_metadata
    resp = @conn.put("transactions/#{id}", body.to_json, auth_header.merge("Content-Type" => "application/json"))
    handle_errors(resp)
    JSON.parse(resp.body)
  end

  private

  def auth_header
    { "Authorization" => "Bearer #{@token}" }
  end

  def handle_errors(resp)
    return if resp.success?
    raise "Lunch Money API error #{resp.status}: #{resp.body}"
  end
end
