# frozen_string_literal: true
require "date"
require "time"
require "matcher"

class Syncer
  def initialize(config:, lm_client:, privacy_client:)
    @config = config
    @lm = lm_client
    @priv = privacy_client
  end

  def run
    end_date = Date.today
    start_date = end_date - @config.days

    puts "Searching #{@config.days} days of transactions..."
    lm_txs = @lm.get_transactions(start_date: start_date.iso8601, end_date: end_date.iso8601)
    priv_txs = @priv.list_transactions(
      begin: start_date.iso8601,
      end: end_date.iso8601,
      result: "APPROVED"
    )

    matches = Matcher.match(lm_transactions: lm_txs, privacy_transactions: priv_txs)

    puts "Found #{matches.size} matches (dry_run=#{@config.dry_run})"

    matches.each do |m|
      puts "  LM##{m[:lm_id]} #{m[:lm_date]} $#{m[:lm_amount]} #{m[:lm_payee]} -> #{m[:suggested_payee]} | Privacy #{m[:privacy_date].to_s[0,10]} $#{format('%.2f', m[:privacy_amount].to_f / 100.0)} (#{m[:privacy_token]})"
      next if @config.dry_run

      meta = m[:lm_custom_metadata].merge(
        "privacy_transaction_token" => m[:privacy_token],
        "privacy_matched_at" => Time.now.utc.iso8601
      )
      @lm.update_transaction(m[:lm_id], payee: m[:suggested_payee], custom_metadata: meta)
      puts "    UPDATED"
    end

    matched_ids = matches.map { |m| m[:lm_id] }
    unmatched = Matcher.unmatched(lm_transactions: lm_txs, matched_ids: matched_ids)

    if unmatched.any?
      puts "Unmatched privacy-named transactions (#{unmatched.size}):"
      unmatched.each do |lm|
        puts "  LM##{lm['id']} #{lm['date']} $#{lm['amount']} #{lm['payee']}"
      end
    end
  end
end
