# frozen_string_literal: true
require "date"

module Matcher
  DATE_WINDOW_DAYS = 2

  def self.match(lm_transactions:, privacy_transactions:)
    privacy_transactions.each_with_object([]) do |p, acc|
      lm_transactions.each do |lm|
        next if already_enriched?(lm)
        if match?(lm, p)
          acc << build_match(lm, p)
          break # one-to-one for simplicity; first LM wins
        end
      end
    end
  end

  def self.already_enriched?(lm)
    meta = lm["custom_metadata"] || {}
    meta["privacy_transaction_token"] && !meta["privacy_transaction_token"].to_s.empty?
  end

  def self.match?(lm, p)
    lm_date = Date.parse(lm["date"])
    p_date = Date.parse(p["created"])
    date_ok = (lm_date - p_date).abs <= DATE_WINDOW_DAYS

    lm_amt = lm["amount"].to_f.abs
    p_amt = (p["amount"].to_f / 100.0).abs
    amt_ok = (lm_amt - p_amt).abs < 0.005 # floating point tolerance for 4 decimals

    date_ok && amt_ok
  end

  def self.build_match(lm, p)
    m = p["merchant"] || {}
    {
      lm_id: lm["id"],
      lm_payee: lm["payee"],
      privacy_token: p["token"],
      suggested_payee: m["descriptor"]
    }
  end
end
