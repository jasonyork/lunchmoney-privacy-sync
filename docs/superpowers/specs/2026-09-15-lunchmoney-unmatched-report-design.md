# Design: Report unmatched "privacy"-named LunchMoney transactions

Date: 2026-09-15

## Goal

When the sync script runs, it currently prints only the matches it found between
LunchMoney transactions and privacy.com transactions. Add reporting of LunchMoney
transactions whose payee contains "privacy" that did **not** match any
privacy.com transaction in the same window.

## Behavior

- Unmatched entries are **always printed** in the run output (no new CLI flag).
- Entries are limited to LM transactions where:
  - payee contains "privacy" (case-insensitive, same rule as `Matcher.privacy_payee?`),
  - `custom_metadata` has no `privacy_transaction_token` (not already enriched),
  - the transaction id did not end up in a match during the current run.
- Already-enriched transactions are **excluded** from the report.
- No persistence changes. No changes to matching or update logic.

## Changes

### `lib/matcher.rb`

Add a pure method:

```
Matcher.unmatched(lm_transactions:, matched_ids:)
```

Returns the subset of `lm_transactions` that satisfy `privacy_payee?`, are not
`already_enriched?`, and whose `id` is not in `matched_ids`.

### `lib/syncer.rb`

In `run`, after matches are computed:

- Derive `matched_ids = matches.map { |m| m[:lm_id] }`.
- Call `Matcher.unmatched(lm_transactions: lm_txs, matched_ids: matched_ids)`.
- Print a header like `Unmatched privacy-named transactions (N):` followed by one
  line per entry using the same detail format as matches
  (`LM#id date $amount payee`). No update is performed for these.

## Tests

- `spec/matcher_spec.rb`: new cases for `Matcher.unmatched`:
  - returns a privacy-named, non-enriched, non-matched tx,
  - excludes a non-privacy payee,
  - excludes an already-enriched tx,
  - excludes a tx that was matched (id present in `matched_ids`).
- `spec/syncer_spec.rb`: assert run output includes the unmatched entries and
  that no update call is made for them.
- `spec/e2e_sync_spec.rb`: update stubs if the run output expectations change.