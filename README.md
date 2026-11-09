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

## Running on a schedule

Re-running is safe, since already-synced transactions are skipped, so a daily
run with the default 14-day window catches everything, including transactions
that post a few days late.

Two things apply wherever you run it:

- **Set `DRY_RUN=false`.** Otherwise every scheduled run only previews.
- **Keep the logs private.** Each run prints transaction dates, amounts and
  merchant names. For example, don't run it from a public repo's GitHub Actions.

### Docker

The included `Dockerfile` builds an image that runs the sync once and exits.
Credentials are never copied into the image (`.env` is excluded in
`.dockerignore`), so pass them at run time:

```bash
docker build -t lunchmoney-privacy-sync .
docker run --rm --env-file .env lunchmoney-privacy-sync                       # dry run
docker run --rm --env-file .env -e DRY_RUN=false lunchmoney-privacy-sync      # real run
```

### Fly.io (scheduled Machine)

Fly can start a Machine on a fuzzy `hourly`, `daily`, `weekly` or `monthly`
schedule. It runs the container, which exits when the sync finishes, and you're
billed only for the seconds it runs.

```bash
# One-time setup
fly apps create lunchmoney-privacy-sync          # pick any unique name
fly secrets set -a lunchmoney-privacy-sync \
  LUNCHMONEY_TOKEN=your_token PRIVACY_API_KEY=your_key

# Build from the local Dockerfile and schedule it (also runs once now)
fly machine run . -a lunchmoney-privacy-sync \
  --schedule daily --restart no \
  --env DRY_RUN=false \
  --vm-size shared-cpu-1x --vm-memory 256
```

App secrets are exposed to the Machine as environment variables. Useful
follow-ups:

```bash
fly logs -a lunchmoney-privacy-sync              # watch the next run's output
fly machine list -a lunchmoney-privacy-sync      # find the Machine ID
fly machine destroy <machine-id> -a lunchmoney-privacy-sync   # stop the schedule
```

To deploy code changes, destroy the old Machine and run the `fly machine run`
command again. Scheduled Machines can't be started by hand, so to test a
change, run it once with `fly machine run . -a lunchmoney-privacy-sync --rm`
(dry run, unless you add `--env DRY_RUN=false`).

Fly picks the exact run time, and a failed run won't alert you, so check
`fly logs` now and then. For alerts, you could wrap the command so it pings a
dead-man's-switch service like [healthchecks.io](https://healthchecks.io) after
each successful run.

### Alternatives

- **macOS launchd:** a LaunchAgent that runs `bin/sync-privacy-lm` daily with
  your local `.env`. Simple, but it only runs while your Mac is awake.
- **GitHub Actions cron:** works well from a *private* repo with the tokens
  stored as repository secrets. Avoid it on a public repo, because the run logs
  are public.

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
