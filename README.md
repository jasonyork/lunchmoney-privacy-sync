# lunchmoney-privacy-sync

A small Ruby CLI that replaces the generic `PRIVACY*…` payee on your
[Lunch Money](https://lunchmoney.app) transactions with the real merchant name
from [Privacy.com](https://privacy.com).

When you pay with a Privacy virtual card, your bank feed (and so Lunch Money)
usually shows something like `PRIVACY*1234` as the payee. Privacy's API knows
the actual merchant. This script matches the two and fixes up the payee.

## How it works

1. Fetches the last N days of transactions from the Lunch Money v2 API and the
   Privacy API (approved transactions only).
2. Considers only Lunch Money transactions whose payee contains "privacy"
   (case-insensitive) and that haven't already been synced.
3. Matches each Privacy transaction to a Lunch Money transaction with the same
   absolute amount and a date within 5 days. Each Lunch Money transaction is
   matched at most once.
4. Skips Privacy refunds and credits (`RETURN` / `CREDIT_AUTHORIZATION` events),
   so a refund never renames the original purchase.
5. For each match, updates the Lunch Money transaction:
   - `payee` → the Privacy `merchant.descriptor`
   - `custom_metadata.privacy_transaction_token` and `privacy_matched_at` are
     added (existing metadata keys are kept). The token marks the transaction as
     synced, so re-running is safe.
6. Lists any privacy-named Lunch Money transactions it couldn't match, so you
   can fix them by hand.

No other fields are changed, and nothing is ever written to Privacy.

## Requirements

- Ruby 3.2+
- A Lunch Money API token (Settings → Developers)
- A Privacy API key (Account → API)

## Setup

```bash
git clone https://github.com/jasonyork/lunchmoney-privacy-sync.git
cd lunchmoney-privacy-sync
bundle install
cp .env.example .env   # then fill in your tokens
```

## Usage

The script **runs in dry-run mode by default**: it prints what it would change
and writes nothing.

```bash
bin/sync-privacy-lm              # preview the last 14 days
bin/sync-privacy-lm --days 30    # preview a longer window
bin/sync-privacy-lm --no-dry-run # actually update Lunch Money
```

| Option / env var                 | Default                      | Description                          |
| -------------------------------- | ---------------------------- | ------------------------------------ |
| `LUNCHMONEY_TOKEN`               | *(required)*                 | Lunch Money v2 bearer token          |
| `PRIVACY_API_KEY`                | *(required)*                 | Privacy API key                      |
| `PRIVACY_BASE_URL`               | `https://api.privacy.com/v1` | Use `https://sandbox.privacy.com/v1` to test |
| `--days N` / `SYNC_DAYS`         | `14`                         | How many days back to look           |
| `--[no-]dry-run` / `DRY_RUN`     | `true`                       | Set `DRY_RUN=false` or pass `--no-dry-run` to write changes |

Command-line flags override environment variables.

### Limitations

- Lunch Money results aren't paginated; the script fetches up to 2,000
  transactions per run, which is plenty for a normal look-back window.
- When several same-amount Privacy purchases fall within the 5-day window, they
  are paired in order. Check the dry-run output if you have repeat charges.

## ⚠️ Caution

This tool edits real financial records. Always review a dry run before using
`--no-dry-run`. It is provided as-is, with no warranty. See the license.

## Development

```bash
bundle exec rspec
```

Tests use WebMock and never touch the real APIs.

## License

[MIT](LICENSE)
