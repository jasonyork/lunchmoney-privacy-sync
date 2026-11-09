# frozen_string_literal: true
require "date"
require "set"

module Matcher
  DATE_WINDOW_DAYS = 5
  CREDIT_EVENT_TYPES = %w[RETURN CREDIT_AUTHORIZATION].freeze

  def self.match(lm_transactions:, privacy_transactions:)
    used_lm_ids = Set.new
    privacy_transactions.each_with_object([]) do |p, acc|
      next if privacy_credit?(p)

      lm = lm_transactions.find do |candidate|
        !used_lm_ids.include?(candidate["id"]) &&
          !already_enriched?(candidate) &&
          privacy_payee?(candidate) &&
          match?(candidate, p)
      end
      next unless lm

      used_lm_ids << lm["id"]
      acc << build_match(lm, p)
    end
  end

  def self.unmatched(lm_transactions:, matched_ids:)
    lm_transactions.select do |lm|
      privacy_payee?(lm) &&
        !already_enriched?(lm) &&
        !matched_ids.include?(lm["id"])
    end
  end

  def self.already_enriched?(lm)
    meta = lm["custom_metadata"] || {}
    meta["privacy_transaction_token"] && !meta["privacy_transaction_token"].to_s.empty?
  end

  def self.privacy_payee?(lm)
    (lm["payee"] || "").downcase.include?("privacy")
  end

  def self.privacy_credit?(p)
    (p["events"] || []).any? { |e| CREDIT_EVENT_TYPES.include?(e["type"]) }
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
      lm_date: lm["date"],
      lm_amount: lm["amount"],
      lm_custom_metadata: lm["custom_metadata"] || {},
      privacy_token: p["token"],
      privacy_date: p["created"],
      privacy_amount: p["amount"],
      suggested_payee: m["descriptor"]
    }
  end
end
