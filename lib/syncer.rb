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

    lm_txs = @lm.get_transactions(start_date: start_date.iso8601, end_date: end_date.iso8601)
    priv_txs = @priv.list_transactions(
      begin: start_date.iso8601,
      end: end_date.iso8601,
      result: "APPROVED"
    )

    matches = Matcher.match(lm_transactions: lm_txs, privacy_transactions: priv_txs)

    puts "Found #{matches.size} matches (dry_run=#{@config.dry_run}, force=#{@config.force})"

    matches.each do |m|
      puts "  LM##{m[:lm_id]} payee -> #{m[:suggested_payee]} (Privacy #{m[:privacy_token]})"
      next if @config.dry_run

      meta = { "privacy_transaction_token" => m[:privacy_token], "privacy_matched_at" => Time.now.utc.iso8601 }
      @lm.update_transaction(m[:lm_id], payee: m[:suggested_payee], custom_metadata: meta)
      puts "    UPDATED"
    end
  end
end
