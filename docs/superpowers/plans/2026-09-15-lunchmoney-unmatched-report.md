# Unmatched Privacy-Named Transaction Report Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the sync script output to report LunchMoney transactions whose payee contains "privacy" that could not be matched to any privacy.com transaction in the window.

**Architecture:** Add a pure `Matcher.unmatched` method that returns privacy-named, non-enriched, non-matched LM transactions given the matched ids. `Syncer#run` derives matched ids from matches, calls `Matcher.unmatched`, and prints a header + one line per entry. No persistence, no new CLI flags, no changes to matching/update behavior.

**Tech Stack:** Ruby 3.2+, RSpec, WebMock (existing).

**Current state (verify before starting):** Working tree has uncommitted changes to `lib/matcher.rb`, `lib/syncer.rb`, `spec/matcher_spec.rb`, `spec/e2e_sync_spec.rb` (DATE_WINDOW_DAYS=4, `privacy_payee?` filter, enriched detail fields). Build on top of them.

---

### Task 1: `Matcher.unmatched` (pure, TDD)

**Files:**
- Modify: `lib/matcher.rb` (append `unmatched` method after `match`)
- Test: `spec/matcher_spec.rb`

- [ ] **Step 1: Write the failing tests** (append to `spec/matcher_spec.rb`)

```ruby
  describe ".unmatched" do
    it "returns privacy-named, non-enriched, non-matched LM tx" do
      unmatched_tx = { "id" => 555, "date" => "2026-05-14", "amount" => "10.00", "payee" => "PRIVACY*9999", "custom_metadata" => {} }
      result = Matcher.unmatched(lm_transactions: [unmatched_tx], matched_ids: [])
      expect(result.map { |t| t["id"] }).to eq([555])
    end

    it "excludes a non-privacy payee" do
      result = Matcher.unmatched(lm_transactions: [lm_tx.merge("payee" => "AMAZON PRIME")], matched_ids: [])
      expect(result).to be_empty
    end

    it "excludes an already-enriched tx" do
      enriched = lm_tx.merge("custom_metadata" => { "privacy_transaction_token" => "already" })
      result = Matcher.unmatched(lm_transactions: [enriched], matched_ids: [])
      expect(result).to be_empty
    end

    it "excludes a tx whose id appears in matched_ids" do
      matched_ids = [lm_tx["id"]]
      result = Matcher.unmatched(lm_transactions: [lm_tx], matched_ids: matched_ids)
      expect(result).to be_empty
    end
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/matcher_spec.rb -v`
Expected: FAIL with `undefined method 'unmatched' for Matcher:Module`

- [ ] **Step 3: Implement `Matcher.unmatched`** (insert after `self.match`, keeping `already_enriched?`/`privacy_payee?` as-is)

```ruby
  def self.unmatched(lm_transactions:, matched_ids:)
    lm_transactions.select do |lm|
      privacy_payee?(lm) &&
        !already_enriched?(lm) &&
        !matched_ids.include?(lm["id"])
    end
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/matcher_spec.rb -v`
Expected: all PASS

- [ ] **Step 5: Commit**

```bash
git add lib/matcher.rb spec/matcher_spec.rb
git commit -m "feat: Matcher.unmatched returns privacy-named txs with no match (TDD)"
```

---

### Task 2: `Syncer#run` prints unmatched entries (TDD)

**Files:**
- Modify: `lib/syncer.rb:25-36`
- Test: `spec/syncer_spec.rb`

- [ ] **Step 1: Write the failing test** (append to `spec/syncer_spec.rb`)

```ruby
  it "prints privacy-named LM tx that matched no privacy tx" do
    lm_client = double("LM")
    priv_client = double("Priv")

    lm_unmatched = { "id" => 777, "date" => Date.today.iso8601, "amount" => "12.3400", "payee" => "PRIVACY*9999", "notes" => nil, "custom_metadata" => {} }
    priv_tx = { "token" => "tok", "amount" => -123456, "created" => "#{Date.today.iso8601}T19:17:22Z", "merchant" => { "descriptor" => "SOMETHING ELSE" } }

    allow(lm_client).to receive(:get_transactions).and_return([lm_unmatched])
    allow(priv_client).to receive(:list_transactions).and_return([priv_tx])

    syncer = Syncer.new(config: cfg, lm_client: lm_client, privacy_client: priv_client)

    expect { syncer.run }.to output(/Unmatched privacy-named transactions \(1\):\n\s+LM#777 2026-.*\$12\.3400 PRIVACY\*9999/m).to_stdout
  end

  it "does not print unmatched header when all privacy-named txs matched" do
    lm_tx = { "id" => 123, "date" => Date.today.iso8601, "amount" => "76.6600", "payee" => "PRIVACY*1234", "notes" => nil, "custom_metadata" => {} }
    priv_tx = { "token" => "tok", "amount" => -7666, "created" => "#{Date.today.iso8601}T19:17:22Z", "merchant" => { "descriptor" => "RESTAURANT ABC" } }

    allow(lm_client).to receive(:get_transactions).and_return([lm_tx])
    allow(priv_client).to receive(:list_transactions).and_return([priv_tx])

    syncer = Syncer.new(config: cfg, lm_client: lm_client, privacy_client: priv_client)

    expect { syncer.run }.not_to output(/Unmatched privacy-named transactions/).to_stdout
    expect { syncer.run }.to output(/Found 1 matches/).to_stdout
  end
```

Note: the second test calls `syncer.run` twice; that is fine because clients are doubles returning the same stubs.

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/syncer_spec.rb -v`
Expected: FAIL — "Unmatched privacy-named transactions" never appears in output

- [ ] **Step 3: Implement** — after the `matches.each` loop, in `run` (its existing body becomes a `each` block; keep indent consistent):

```ruby
    matched_ids = matches.map { |m| m[:lm_id] }
    unmatched = Matcher.unmatched(lm_transactions: lm_txs, matched_ids: matched_ids)

    if unmatched.any?
      puts "Unmatched privacy-named transactions (#{unmatched.size}):"
      unmatched.each do |lm|
        puts "  LM##{lm['id']} #{lm['date']} $#{lm['amount']} #{lm['payee']}"
      end
    end
```

- [ ] **Step 4: Run the full syncer spec to verify**

Run: `bundle exec rspec spec/syncer_spec.rb -v`
Expected: all PASS (existing 2 tests + 2 new ones)

- [ ] **Step 5: Commit**

```bash
git add lib/syncer.rb spec/syncer_spec.rb
git commit -m "feat: Syncer prints unmatched privacy-named transactions in output (TDD)"
```

---

### Task 3: e2e coverage + full suite verification

**Files:**
- Modify: `spec/e2e_sync_spec.rb`

- [ ] **Step 1: Add an unmatched LM transaction to the e2e stub and assert output**

Replace the LM `stub_request` `to_return` body in `spec/e2e_sync_spec.rb` so the transactions array contains a second, non-matching privacy-named tx:

```ruby
      .to_return(body: { transactions: [
        { "id" => 42, "date" => "2026-06-01", "amount" => "42.0000", "payee" => "PRIVACY*1234", "notes" => nil, "custom_metadata" => {} },
        { "id" => 43, "date" => "2026-06-02", "amount" => "9.9900", "payee" => "PRIVACY*9999", "notes" => nil, "custom_metadata" => {} }
      ], has_more: false }.to_json)
```

Then wrap the `Syncer.new(...).run` call in an output matcher and add an assertion after `expect(update_stub)...`:

```ruby
    expect { Syncer.new(config: cfg, lm_client: lm_client, privacy_client: priv_client).run }
      .to output(/Unmatched privacy-named transactions \(1\):.*LM#43 2026-06-02 \$9\.9900 PRIVACY\*9999/m).to_stdout
```

(Replace the standalone `Syncer.new(...).run` line with the wrapped form so the output is captured only once; keep the `update_stub` assertion as is.)

- [ ] **Step 2: Run the e2e spec**

Run: `bundle exec rspec spec/e2e_sync_spec.rb -v`
Expected: PASS (update_stub requested once, unmatched header printed)

- [ ] **Step 3: Run the full suite**

Run: `bundle exec rspec --format documentation`
Expected: all examples PASS

- [ ] **Step 4: Commit**

```bash
git add spec/e2e_sync_spec.rb
git commit -m "test: e2e covers unmatched privacy-named tx in output"
```

---

**Plan complete and saved to `docs/superpowers/plans/2026-09-15-lunchmoney-unmatched-report.md`.**

Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using the executing-plans skill, batch with checkpoints for review.

Which approach?