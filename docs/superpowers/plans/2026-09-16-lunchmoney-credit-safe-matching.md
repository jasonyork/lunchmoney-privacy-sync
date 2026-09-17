# Credit-Safe Matching Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Exclude privacy refund/credit transactions from being match candidates so a return can never be matched to an unrelated privacy-named LunchMoney transaction.

**Architecture:** Add a pure `Matcher.privacy_credit?` predicate and skip credit events (`RETURN`, `CREDIT_AUTHORIZATION` in `events`) at the top of the privacy-transaction loop in `Matcher.match`. Uses the canonical event-type signal only — never amount sign. No syncer/CLI/persistence changes.

**Tech Stack:** Ruby 3.2+, RSpec, WebMock (existing).

**Current `lib/matcher.rb` (build on top of this):**

```ruby
# frozen_string_literal: true
require "date"

module Matcher
  DATE_WINDOW_DAYS = 4

  def self.match(lm_transactions:, privacy_transactions:)
    privacy_transactions.each_with_object([]) do |p, acc|
      lm_transactions.each do |lm|
        next if already_enriched?(lm)
        next unless privacy_payee?(lm)
        if match?(lm, p)
          acc << build_match(lm, p)
          break # one-to-one for simplicity; first LM wins
        end
      end
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
      privacy_token: p["token"],
      privacy_date: p["created"],
      privacy_amount: p["amount"],
      suggested_payee: m["descriptor"]
    }
  end
end
```

The current `spec/matcher_spec.rb` defines `let(:lm_tx)` (id 123, date "2026-05-15", amount "76.6600", payee "PRIVACY*1234", `custom_metadata => {}`) and `let(:priv_tx)` (token "764fa5a3-...", `amount => -7666` cents, created "2026-05-15T19:17:22Z", merchant descriptor "RESTAURANT ABC"). Note `priv_tx` has **no `events` key**.

---

### Task 1: `Matcher.privacy_credit?` + skip in `match` (pure, TDD)

**Files:**
- Modify: `lib/matcher.rb`
- Test: `spec/matcher_spec.rb`

- [ ] **Step 1: Write the failing tests** (append to `spec/matcher_spec.rb`, inside the existing `RSpec.describe Matcher do` block)

```ruby
  it "does not match a refund privacy tx (RETURN event)" do
    priv_refund = priv_tx.merge("events" => [{ "type" => "RETURN", "amount" => 7666 }])
    matches = Matcher.match(lm_transactions: [lm_tx], privacy_transactions: [priv_refund])
    expect(matches).to be_empty
  end

  it "does not match a credit privacy tx (CREDIT_AUTHORIZATION event)" do
    priv_credit = priv_tx.merge("events" => [{ "type" => "CREDIT_AUTHORIZATION", "amount" => 7666 }])
    matches = Matcher.match(lm_transactions: [lm_tx], privacy_transactions: [priv_credit])
    expect(matches).to be_empty
  end

  it "matches a negative-amount privacy tx with only purchase events (amount sign is not the discriminator)" do
    priv_purchase = priv_tx.merge("events" => [{ "type" => "AUTHORIZATION", "amount" => 7666 }, { "type" => "CLEARING", "amount" => 7666 }])
    matches = Matcher.match(lm_transactions: [lm_tx], privacy_transactions: [priv_purchase])
    expect(matches.size).to eq(1)
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/matcher_spec.rb --format documentation`
Expected: the two new credit tests FAIL (the credit txs currently match); the purchase test is already passing (existing behavior). That is the expected RED baseline — the failing tests prove the exclusion isn't yet implemented.

- [ ] **Step 3: Implement** (in `lib/matcher.rb`: add the skip line at the top of the privacy loop in `match`, add a `CREDIT_EVENT_TYPES` constant after `DATE_WINDOW_DAYS`, and add the `privacy_credit?` method after `privacy_payee?`)

```ruby
  DATE_WINDOW_DAYS = 4
  CREDIT_EVENT_TYPES = %w[RETURN CREDIT_AUTHORIZATION].freeze
```

```ruby
  def self.match(lm_transactions:, privacy_transactions:)
    privacy_transactions.each_with_object([]) do |p, acc|
      next if privacy_credit?(p)
      lm_transactions.each do |lm|
```

```ruby
  def self.privacy_credit?(p)
    (p["events"] || []).any? { |e| CREDIT_EVENT_TYPES.include?(e["type"]) }
  end
```

- [ ] **Step 4: Run the full matcher spec to verify**

Run: `bundle exec rspec spec/matcher_spec.rb --format documentation`
Expected: all examples PASS (existing 10 + 3 new = 13)

- [ ] **Step 5: Run the full suite**

Run: `bundle exec rspec --format documentation`
Expected: all examples PASS (existing 20 + 3 new = 23)

- [ ] **Step 6: Commit**

```bash
git add lib/matcher.rb spec/matcher_spec.rb
git commit -m "feat: exclude privacy refund/credit txs (RETURN, CREDIT_AUTHORIZATION) from matching (TDD)"
```

---

**Plan complete and saved to `docs/superpowers/plans/2026-09-16-lunchmoney-credit-safe-matching.md`.**

Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using the executing-plans skill, batch with checkpoints for review.

Which approach?