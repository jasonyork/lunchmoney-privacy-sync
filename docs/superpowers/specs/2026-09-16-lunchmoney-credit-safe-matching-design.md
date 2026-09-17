# Design: Credit-safe matching (exclude privacy refunds/credits as match candidates)

Date: 2026-09-16

## Background / research findings

Live verification of the consumer Privacy.com API (384 approved transactions,
June–Sept 2026) established:

- The `funding` array (documented with `type: "PROMO"` for promotional credits) is
  **never returned** on a consumer account. It is an Issuing-only field. The gross
  vs. net credit split for a purchase is therefore **not available** from the
  consumer transaction API.
- Refunds/credits arrive as separate, negative-amount transactions whose `events`
  contain `RETURN` and/or `CREDIT_AUTHORIZATION` types.
- Amount sign is not a reliable credit signal: some docs/examples use negative
  amounts for debits, while live purchases come back positive.
- FX transactions differ in `merchant.amount` (local currency) only; the top-level
  `amount` is already in card currency (USD), so amount matching stays correct.

## Goal

Keep gross-amount matching, but exclude privacy refund/credit transactions from
being match candidates so a return cannot be matched to — and used to "enrich" —
an unrelated privacy-named LunchMoney transaction of the same absolute amount.

## Behavior

- A privacy transaction is excluded from matching if any of its `events` has type
  `RETURN` or `CREDIT_AUTHORIZATION`.
- Transactions with no `events` field (or an empty list) remain eligible (backward
  compatible with existing fixtures/specs).
- Amount matching logic, date window, `privacy_payee?`, `already_enriched?`, and
  `Matcher.unmatched` are unchanged.
- No syncer/CLI/persistence changes.

## Changes

### `lib/matcher.rb`

Add a pure predicate:

```
Matcher.privacy_credit?(privacy_tx)
```

Returns `true` when `privacy_tx["events"]` (or `[]` if absent) contains any event
with `type` equal to `"RETURN"` or `"CREDIT_AUTHORIZATION"`.

In `Matcher.match`, at the top of the per-privacy-transaction loop, add
`next if privacy_credit?(p)`.

### Tests (`spec/matcher_spec.rb`)

- A privacy tx with a `RETURN` event does not match.
- A privacy tx with a `CREDIT_AUTHORIZATION` event does not match.
- A negative-amount privacy tx with no credit events (docs-convention purchase)
  still matches.
- Existing specs are untouched and must continue to pass (they use transactions
  with no `events`, which remain eligible).