# Lunch Money + Privacy.com Integration Script Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a small, safe, standalone Ruby CLI script that fetches the most recent transactions from the Lunch Money v2 API, fetches recent transactions from the Privacy.com API, attempts to match Privacy transactions to Lunch Money ones (by amount and date proximity), and updates only the Lunch Money transaction's `payee` field to the Privacy `merchant.descriptor` value (while also recording the Privacy transaction token in `custom_metadata.privacy_transaction_token` for idempotency). The script must be idempotent, support dry-run, and be developed with TDD.

**Architecture:** One small Ruby project. Thin executable in `bin/`. Two API client classes (one per service) using Faraday for HTTP, retries, and JSON. A pure `Matcher` module for matching logic. A `Syncer` orchestrator. Configuration loaded from environment variables (with optional dotenv). The only data field changed on a Lunch Money transaction is `payee` (set to Privacy's `merchant.descriptor`); `custom_metadata.privacy_transaction_token` is also written for idempotency tracking. All state changes to Lunch Money go through `PUT /v2/transactions/{id}`. Tests use RSpec + WebMock with recorded sample payloads derived from the public mock and official docs. No persistent storage, no web UI, no card creation — read recent tx + conditional update only.

**Tech Stack:**
- Ruby 3.2+
- Faraday + faraday-retry (for both APIs)
- RSpec, WebMock (testing)
- dotenv (optional, dev)
- Standard library (optparse, time, etc.)
- Git for frequent commits

**Key API facts captured during research (do not deviate):**
- Lunch Money base: `https://api.lunchmoney.dev/v2`
  - Auth: `Authorization: Bearer <token>`
  - GET /v2/transactions?start_date=YYYY-MM-DD&end_date=YYYY-MM-DD&limit=2000&include_metadata=true → `{ transactions: [...], has_more: bool }`
  - Transaction shape (from live mock): `{ id, date, amount: "1250.8400", currency, payee, notes, original_name, is_pending, status, manual_account_id, plaid_account_id, custom_metadata, created_at, updated_at, ... }`
  - PUT /v2/transactions/{id} body with updatable fields (e.g. `{ payee: "MERCHANT NAME", custom_metadata: { "privacy_transaction_token": "..." } }`)
  - Rate limit: 100 req/min per IP; respect Retry-After + X-RateLimit-* headers.
- Privacy.com base: `https://api.privacy.com/v1` (prod) or `https://sandbox.privacy.com/v1`
  - Auth: `Authorization: api-key <key>` (literal prefix "api-key ")
  - GET /v1/transactions?begin=YYYY-MM-DD&end=YYYY-MM-DD&page=1&page_size=50&result=APPROVED → `{ data: [tx...], page, total_pages, total_entries }`
  - Transaction shape (from docs): `{ token, amount (cents, integer), created (ISO), status, result, merchant: { descriptor, city, state, country, mcc, acceptor_id }, card: { token, last_four, memo, ... }, events: [...] }`
  - Amounts in cents; signs may differ from LM — always match on absolute value after converting cents→dollars.

**Safety invariants (must be enforced in code and docs):**
- Never run against real budget without first creating and switching to a test budget (per LM getting-started guide).
- Default to dry-run.
- Only update transactions that do not already have a `custom_metadata.privacy_transaction_token`.
- Log every proposed change; in dry-run, stop before the PUT.
- Support `--force` to re-apply (overwrites payee + custom_metadata even if token already present).

---

### Task 1: Project scaffolding and dependencies

**Files:**
- Create: `Gemfile`
- Create: `.gitignore`
- Create: `bin/sync-privacy-lm`
- Run: `bundle install`

- [ ] **Step 1: Write Gemfile (pinned, minimal runtime + test group)**

```ruby
# frozen_string_literal: true
source "https://rubygems.org"

ruby ">= 3.2.0"

gem "faraday", "~> 2.12"
gem "faraday-retry", "~> 2.2"

group :development, :test do
  gem "rspec", "~> 3.13"
  gem "webmock", "~> 3.23"
  gem "dotenv", "~> 3.0"
end
```

- [ ] **Step 2: Create .gitignore**

```
# .gitignore
# Git worktrees (required for superpowers subagent-driven-development isolation)
.worktrees/

# IDE
.idea/
*.iml

/.bundle/
/vendor/bundle
/.env
/.env.*
/log/
/tmp/
*.gem
*.rbc
```

- [ ] **Step 3: Create bin/sync-privacy-lm (will be filled later; make executable skeleton)**

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true
# bin/sync-privacy-lm
require "optparse"
# TODO: wire up in later tasks
puts "Sync script placeholder - implement in Task 7"
```

- [ ] **Step 4: Run bundle install and make bin executable**

```bash
bundle install
chmod +x bin/sync-privacy-lm
```

- [ ] **Step 5: git init + first commit (if no repo)**

```bash
git init
git add Gemfile .gitignore bin/sync-privacy-lm
git commit -m "chore: initialize ruby project with faraday + rspec + webmock"
```

- [ ] **Step 6: Verify**

```bash
bundle exec ruby -e 'puts "Ruby OK"; require "faraday"; puts "Faraday OK"'
ls -l bin/sync-privacy-lm
```

---

### Task 2: Configuration and environment handling (TDD)

**Files:**
- Create: `lib/config.rb`
- Create: `spec/config_spec.rb`
- Modify: `Gemfile` (already has dotenv in dev group)

- [ ] **Step 1: Write failing test for Config**

```ruby
# spec/config_spec.rb
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
end
```

- [ ] **Step 2: Run test (expect failure)**

```bash
bundle exec rspec spec/config_spec.rb -v
# Expected: failures about uninitialized constant Config and missing keys
```

- [ ] **Step 3: Implement minimal Config**

```ruby
# lib/config.rb
# frozen_string_literal: true
require "dotenv/load" if ENV["RACK_ENV"] != "production" # harmless in script

class Config
  attr_reader :lunchmoney_token, :privacy_api_key, :privacy_base_url, :days, :dry_run, :force

  def initialize(lunchmoney_token:, privacy_api_key:, privacy_base_url: nil, days: 14, dry_run: true, force: false)
    @lunchmoney_token = lunchmoney_token
    @privacy_api_key = privacy_api_key
    @privacy_base_url = privacy_base_url || "https://api.privacy.com/v1"
    @days = days
    @dry_run = dry_run
    @force = force
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
      dry_run: ENV.fetch("DRY_RUN", "true") != "false",
      force: ENV.fetch("FORCE", "false") == "true"
    )
  end
end
```

- [ ] **Step 4: Run test until green**

```bash
bundle exec rspec spec/config_spec.rb -v
# Expected: PASS
```

- [ ] **Step 5: Commit**

```bash
git add lib/config.rb spec/config_spec.rb
git commit -m "feat: add Config with env loading and validation (TDD)"
```

---

### Task 3: Privacy.com API client (TDD)

**Files:**
- Create: `lib/privacy_client.rb`
- Create: `spec/privacy_client_spec.rb`

- [ ] **Step 1: Write failing spec with realistic Privacy payload**

```ruby
# spec/privacy_client_spec.rb
require "privacy_client"

RSpec.describe PrivacyClient do
  let(:api_key) { "priv_test" }
  let(:client) { PrivacyClient.new(api_key: api_key, base_url: "https://sandbox.privacy.com/v1") }

  it "lists transactions with correct auth header and pagination params" do
    stub = stub_request(:get, "https://sandbox.privacy.com/v1/transactions")
      .with(
        headers: { "Authorization" => "api-key priv_test" },
        query: hash_including("begin" => "2026-05-01", "end" => "2026-05-31", "page" => "1", "page_size" => "50", "result" => "APPROVED")
      )
      .to_return(
        status: 200,
        body: {
          data: [
            {
              "token" => "764fa5a3-2371-40f0-8cbb-9a2e1230d955",
              "amount" => -7666,
              "created" => "2026-05-15T19:17:22Z",
              "status" => "SETTLING",
              "result" => "APPROVED",
              "merchant" => {
                "descriptor" => "RESTAURANT ABC",
                "city" => "NEW YORK",
                "state" => "NY",
                "country" => "USA",
                "mcc" => "5812"
              },
              "card" => {
                "token" => "079d1898-65f7-4d66-b0bc-172d2935a5fa",
                "last_four" => "6749",
                "memo" => "dining card"
              }
            }
          ],
          page: 1,
          total_entries: 1,
          total_pages: 1
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    txs = client.list_transactions(begin: "2026-05-01", end: "2026-05-31", result: "APPROVED")
    expect(txs.size).to eq(1)
    expect(txs.first["merchant"]["descriptor"]).to eq("RESTAURANT ABC")
    expect(WebMock).to have_requested(:get, /transactions/).with(headers: { "Authorization" => "api-key priv_test" })
  end
end
```

- [ ] **Step 2: Run (expect failure)**

```bash
bundle exec rspec spec/privacy_client_spec.rb -v
```

- [ ] **Step 3: Implement PrivacyClient (handle pagination loop, Faraday with retry)**

```ruby
# lib/privacy_client.rb
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
  def list_transactions(begin: nil, end: nil, result: "APPROVED", page_size: 50)
    all = []
    page = 1
    loop do
      resp = @conn.get("/transactions", {
        begin: binding.local_variable_get(:begin),
        end: binding.local_variable_get(:end),
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
```

- [ ] **Step 4: Run until green + edge (empty data, 401)**

```bash
bundle exec rspec spec/privacy_client_spec.rb -v
```

- [ ] **Step 5: Commit**

```bash
git add lib/privacy_client.rb spec/privacy_client_spec.rb
git commit -m "feat: PrivacyClient#list_transactions with pagination and auth (TDD)"
```

---

### Task 4: Lunch Money v2 API client (TDD)

**Files:**
- Create: `lib/lunchmoney_client.rb`
- Create: `spec/lunchmoney_client_spec.rb`

- [ ] **Step 1: Write failing spec using exact shape from live mock**

```ruby
# spec/lunchmoney_client_spec.rb
require "lunchmoney_client"

RSpec.describe LunchMoneyClient do
  let(:token) { "lm_test" }
  let(:client) { LunchMoneyClient.new(token: token) }

  it "fetches transactions with include_metadata=true and date filters" do
    stub_request(:get, "https://api.lunchmoney.dev/v2/transactions")
      .with(
        headers: { "Authorization" => "Bearer lm_test" },
        query: hash_including("start_date" => "2026-05-01", "end_date" => "2026-05-31", "limit" => "2000", "include_metadata" => "true")
      )
      .to_return(
        status: 200,
        body: {
          transactions: [
            {
              "id" => 2112150655,
              "date" => "2026-05-28",
              "amount" => "12.3400",
              "currency" => "usd",
              "payee" => "PRIVACY*1234",
              "notes" => nil,
              "original_name" => "PRIVACY.COM",
              "is_pending" => false,
              "custom_metadata" => {}
            }
          ],
          has_more: false
        }.to_json
      )

    txs = client.get_transactions(start_date: "2026-05-01", end_date: "2026-05-31")
    expect(txs.first["payee"]).to eq("PRIVACY*1234")
    expect(txs.first["amount"]).to eq("12.3400")
  end

  it "updates a transaction payee (from privacy merchant.descriptor) and custom_metadata via PUT" do
    stub = stub_request(:put, "https://api.lunchmoney.dev/v2/transactions/2112150655")
      .with(
        headers: { "Authorization" => "Bearer lm_test", "Content-Type" => "application/json" },
        body: hash_including("payee" => "RESTAURANT ABC", "custom_metadata" => { "privacy_transaction_token" => "764fa5a3-..." })
      )
      .to_return(status: 200, body: { id: 2112150655 }.to_json)

    result = client.update_transaction(2112150655, payee: "RESTAURANT ABC", custom_metadata: { "privacy_transaction_token" => "764fa5a3-..." })
    expect(result["id"]).to eq(2112150655)
  end
end
```

- [ ] **Step 2: Run (expect red)**

```bash
bundle exec rspec spec/lunchmoney_client_spec.rb -v
```

- [ ] **Step 3: Implement LunchMoneyClient**

```ruby
# lib/lunchmoney_client.rb
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
    resp = @conn.get("/transactions", {
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
    resp = @conn.put("/transactions/#{id}", body.to_json, auth_header.merge("Content-Type" => "application/json"))
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
```

- [ ] **Step 4: Iterate until all tests pass (add 429/retry behavior test if time)**

```bash
bundle exec rspec spec/lunchmoney_client_spec.rb -v
```

- [ ] **Step 5: Commit**

```bash
git add lib/lunchmoney_client.rb spec/lunchmoney_client_spec.rb
git commit -m "feat: LunchMoneyClient get + update with include_metadata and custom_metadata (TDD)"
```

---

### Task 5: Matching logic (pure, TDD, handles cents vs dollars + signs)

**Files:**
- Create: `lib/matcher.rb`
- Create: `spec/matcher_spec.rb`

- [ ] **Step 1: Write comprehensive failing matcher specs**

```ruby
# spec/matcher_spec.rb
require "matcher"

RSpec.describe Matcher do
  let(:lm_tx) do
    { "id" => 123, "date" => "2026-05-15", "amount" => "76.6600", "payee" => "PRIVACY*1234", "notes" => nil, "custom_metadata" => {} }
  end
  let(:priv_tx) do
    {
      "token" => "764fa5a3-2371-40f0-8cbb-9a2e1230d955",
      "amount" => -7666, # cents, negative in this example
      "created" => "2026-05-15T19:17:22Z",
      "merchant" => { "descriptor" => "RESTAURANT ABC", "city" => "NEW YORK", "state" => "NY", "mcc" => "5812" },
      "card" => { "last_four" => "6749", "memo" => "dining" }
    }
  end

  it "matches on absolute amount (cents vs dollars) and same date" do
    matches = Matcher.match(lm_transactions: [lm_tx], privacy_transactions: [priv_tx])
    expect(matches.size).to eq(1)
    expect(matches.first[:lm_id]).to eq(123)
    expect(matches.first[:privacy_token]).to eq("764fa5a3-...")
    expect(matches.first[:suggested_payee]).to eq("RESTAURANT ABC")
  end

  it "skips LM tx that already has privacy_transaction_token in custom_metadata" do
    lm_enriched = lm_tx.merge("custom_metadata" => { "privacy_transaction_token" => "already" })
    matches = Matcher.match(lm_transactions: [lm_enriched], privacy_transactions: [priv_tx])
    expect(matches).to be_empty
  end

  it "tolerates 2-day date window and different signs" do
    lm_off = lm_tx.merge("date" => "2026-05-17", "amount" => "-76.6600")
    matches = Matcher.match(lm_transactions: [lm_off], privacy_transactions: [priv_tx])
    expect(matches.size).to eq(1)
  end
end
```

- [ ] **Step 2: Run (red)**

```bash
bundle exec rspec spec/matcher_spec.rb -v
```

- [ ] **Step 3: Implement Matcher (YAGNI: simple absolute-amount + date window, first match wins, no fancy scoring)**

```ruby
# lib/matcher.rb
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
      privacy_token: p["token"],
      suggested_payee: m["descriptor"]
    }
  end
end
```

- [ ] **Step 4: Run until green, add 1-2 more cases (amount delta >0.01 fails, already-enriched skipped)**

```bash
bundle exec rspec spec/matcher_spec.rb -v
```

- [ ] **Step 5: Commit**

```bash
git add lib/matcher.rb spec/matcher_spec.rb
git commit -m "feat: pure Matcher with abs amount + date window + idempotency skip (TDD)"
```

---

### Task 6: Syncer orchestrator

**Files:**
- Create: `lib/syncer.rb`
- Create: `spec/syncer_spec.rb`

- [ ] **Step 1: Failing spec (uses doubles for clients)**

```ruby
# spec/syncer_spec.rb
require "syncer"
require "config"

RSpec.describe Syncer do
  let(:cfg) { Config.new(lunchmoney_token: "lm", privacy_api_key: "p", dry_run: true, days: 7, force: false) }
  let(:lm_client) { double("LM") }
  let(:priv_client) { double("Priv") }
  let(:syncer) { Syncer.new(config: cfg, lm_client: lm_client, privacy_client: priv_client) }

  it "fetches from both, matches, and does nothing in dry_run" do
    allow(lm_client).to receive(:get_transactions).and_return([])
    allow(priv_client).to receive(:list_transactions).and_return([])
    expect(lm_client).not_to receive(:update_transaction)
    syncer.run
  end
end
```

- [ ] **Step 2: Run red**

```bash
bundle exec rspec spec/syncer_spec.rb -v
```

- [ ] **Step 3: Implement Syncer (compute window from cfg.days, call matcher, conditional update + logging)**

```ruby
# lib/syncer.rb
# frozen_string_literal: true
require "date"
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
```

- [ ] **Step 4: Make tests pass (add non-dry-run happy path with expectations on update call)**

```bash
bundle exec rspec spec/syncer_spec.rb -v
```

- [ ] **Step 5: Commit**

```bash
git add lib/syncer.rb spec/syncer_spec.rb
git commit -m "feat: Syncer orchestrates fetch+match+conditional update (TDD)"
```

---

### Task 7: CLI entrypoint and .env.example

**Files:**
- Modify: `bin/sync-privacy-lm`
- Create: `.env.example`
- Modify: `README.md` (will expand in Task 10)

- [ ] **Step 1: Implement the bin script (parses options, loads config, wires clients, runs)**

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true
# bin/sync-privacy-lm

require "optparse"
require_relative "../lib/config"
require_relative "../lib/lunchmoney_client"
require_relative "../lib/privacy_client"
require_relative "../lib/syncer"

options = { dry_run: true, days: nil, force: false }

parser = OptionParser.new do |opts|
  opts.banner = "Usage: bin/sync-privacy-lm [options]"
  opts.on("--no-dry-run", "Actually perform updates (default is dry-run)") { options[:dry_run] = false }
  opts.on("--days N", Integer, "Look back N days (default from env or 14)") { |n| options[:days] = n }
  opts.on("--force", "Re-apply even if privacy_transaction_token already present") { options[:force] = true }
  opts.on("-h", "--help", "Show this help") { puts opts; exit }
end
parser.parse!

cfg = Config.load
cfg = Config.new(
  lunchmoney_token: cfg.lunchmoney_token,
  privacy_api_key: cfg.privacy_api_key,
  privacy_base_url: cfg.privacy_base_url,
  days: options[:days] || cfg.days,
  dry_run: options[:dry_run],
  force: options[:force] || cfg.force
)

lm = LunchMoneyClient.new(token: cfg.lunchmoney_token)
priv = PrivacyClient.new(api_key: cfg.privacy_api_key, base_url: cfg.privacy_base_url)

Syncer.new(config: cfg, lm_client: lm, privacy_client: priv).run
```

- [ ] **Step 2: Create .env.example**

```
LUNCHMONEY_TOKEN=your_lm_v2_bearer_token_here
PRIVACY_API_KEY=api-key_here_from_privacy_account_page
# PRIVACY_BASE_URL=https://sandbox.privacy.com/v1   # uncomment for sandbox
# SYNC_DAYS=30
# DRY_RUN=false
# FORCE=false
```

- [ ] **Step 3: Make executable and test help**

```bash
chmod +x bin/sync-privacy-lm
bundle exec bin/sync-privacy-lm --help
```

- [ ] **Step 4: Commit**

```bash
git add bin/sync-privacy-lm .env.example
git commit -m "feat: CLI bin/sync-privacy-lm with --dry-run/--force/--days (TDD via manual + later e2e)"
```

---

### Task 8: End-to-end test with WebMock (full flow)

**Files:**
- Create: `spec/e2e_sync_spec.rb`

- [ ] **Step 1: Write e2e spec that stubs both full responses and asserts correct update body**

```ruby
# spec/e2e_sync_spec.rb
require "syncer"
require "config"

RSpec.describe "end-to-end sync" do
  it "fetches, matches one tx, and calls update with correct payload when not dry-run" do
    cfg = Config.new(lunchmoney_token: "lm", privacy_api_key: "pk", dry_run: false, days: 30)

    lm_client = LunchMoneyClient.new(token: "lm")
    priv_client = PrivacyClient.new(api_key: "pk")

    # LM list (include_metadata true is inside client)
    stub_request(:get, /lunchmoney.dev\/v2\/transactions/)
      .to_return(body: { transactions: [ { "id" => 42, "date" => "2026-06-01", "amount" => "42.0000", "payee" => "PRIV", "notes" => nil, "custom_metadata" => {} } ], has_more: false }.to_json)

    # Privacy list
    stub_request(:get, /privacy.com\/v1\/transactions/)
      .to_return(body: { data: [ { "token" => "tok-xyz", "amount" => 4200, "created" => "2026-06-01T12:00:00Z", "merchant" => { "descriptor" => "CAFE X", "city" => "SF", "state" => "CA", "mcc" => "5812" }, "card" => { "last_four" => "0001", "memo" => "test" } } ], page: 1, total_pages: 1 }.to_json)

    # The PUT we care about
    update_stub = stub_request(:put, "https://api.lunchmoney.dev/v2/transactions/42")
      .with(body: hash_including("payee" => "CAFE X", "custom_metadata" => { "privacy_transaction_token" => "tok-xyz" }))
      .to_return(body: { id: 42 }.to_json)

    Syncer.new(config: cfg, lm_client: lm_client, privacy_client: priv_client).run

    expect(update_stub).to have_been_requested.once
  end
end
```

- [ ] **Step 2: Run until green**

```bash
bundle exec rspec spec/e2e_sync_spec.rb -v
```

- [ ] **Step 3: Commit**

```bash
git add spec/e2e_sync_spec.rb
git commit -m "test: e2e flow with full WebMock stubs for both APIs"
```

---

### Task 9: README, safety warnings, usage, and .env instructions

**Files:**
- Create/Modify: `README.md`

- [ ] **Step 1: Write clear README (include exact header warning about test budget)**

```markdown
# private-lunchmoney

Ruby script that enriches Lunch Money transactions using data from Privacy.com virtual cards.

## ⚠️ Safety First (read this)

- The v2 API changes are **permanent**. Always create a **test budgeting account** first (see https://alpha.lunchmoney.dev/v2/getting-started).
- Default mode is **dry-run**. Nothing is written until you pass `--no-dry-run`.
- The script only touches transactions in the date window you specify.
- Idempotency: transactions that already carry `custom_metadata.privacy_transaction_token` are skipped (unless `--force`).

## Setup

1. `git clone ... && cd private-lunchmoney`
2. `bundle install`
3. Copy `.env.example` → `.env` and fill tokens (never commit `.env`)
4. Get tokens:
   - Lunch Money: https://my.lunchmoney.app/developers (use a token for your **test** budget)
   - Privacy: Account → API Keys

## Run

```bash
# Preview only (safe)
bundle exec bin/sync-privacy-lm --days 14

# Actually write (after verifying in dry-run + test budget)
bundle exec bin/sync-privacy-lm --no-dry-run --days 7

# Force re-enrichment
bundle exec bin/sync-privacy-lm --no-dry-run --force
```

## How matching works

- Date within ±2 days
- Absolute amount match (Privacy cents ↔ Lunch Money decimal dollars)
- Skips any LM tx that already has a `privacy_transaction_token` in custom_metadata
- On match: sets `payee` to the Privacy `merchant.descriptor` value. Also stores the Privacy transaction token in `custom_metadata.privacy_transaction_token` (for idempotency). No other fields on the Lunch Money transaction are modified.

## Environment variables

See `.env.example`.

## Development

```bash
bundle exec rspec
```

## License

MIT
```

- [ ] **Step 2: Commit docs**

```bash
git add README.md
git commit -m "docs: README with safety warnings, usage, and matching rules"
```

---

### Task 10: Final verification, lint, and polish

- [ ] **Step 1: Run full test suite**

```bash
bundle exec rspec --format documentation
# All specs must be green
```

- [ ] **Step 2: Quick smoke of the bin (help + early config error)**

```bash
bundle exec bin/sync-privacy-lm --help
LUNCHMONEY_TOKEN= LM_TOKEN_PRIVACY_API_KEY=foo bundle exec bin/sync-privacy-lm 2>&1 | cat
# Should complain about missing LUNCHMONEY_TOKEN
```

- [ ] **Step 3: (Optional but recommended) Add standardrb or rubocop dev dep + config + run**

If adding:
```bash
bundle add --group development standard
echo 'gem "standard", "~> 1.0", group: :development' >> Gemfile
bundle install
bundle exec standardrb --fix
git add .standard.yml Gemfile* && git commit -m "chore: add standardrb for formatting"
```

- [ ] **Step 4: Final commit of any stray changes**

```bash
git status
git add -A
git commit -m "chore: final verification and polish before handoff" || echo "nothing to commit"
```

- [ ] **Step 5: Print summary of what was built**

```bash
echo "=== Files ==="; find . -type f \( -name "*.rb" -o -name "Gemfile*" -o -name "README*" -o -name ".env*" -o -name ".gitignore" \) | sort
echo "=== Last 5 commits ==="; git log --oneline -5
```

---

**Plan complete and saved to `docs/superpowers/plans/2026-06-12-lunchmoney-privacy-sync.md`.**

Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task (or per logical group), review between tasks, fast iteration. Requires invoking the `subagent-driven-development` skill.

**2. Inline Execution** — Execute tasks in this session using the `executing-plans` skill, batch with explicit checkpoints after major sections (e.g. after clients, after matcher+syncer, after CLI+tests).

Which approach?
