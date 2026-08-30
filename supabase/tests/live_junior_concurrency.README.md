# Live junior concurrency acceptance

`live_junior_concurrency.mjs` is the two-backend-session test that cannot be
expressed by the single-session pgTAP suite. It targets the deployed 科粤版
junior contract and deliberately creates lock contention; it is not run by the
normal local test command.

## Safety boundary

- Use a direct Supabase connection or the Supavisor **session-mode** endpoint on
  port 5432. Transaction-mode port 6543 is rejected because the test needs a
  stable backend for each transaction and advisory lock.
- The URL is read only from `LIVE_JUNIOR_DATABASE_URL`; it is never printed.
  Hosted connections verify the TLS certificate. A custom PEM CA can be passed
  in `LIVE_JUNIOR_DATABASE_CA`.
- The harness takes a suite-wide advisory lock so two copies cannot overlap.
- It creates one random, deterministic-ID **staged** release and one temporary
  student/plan/session. The release is never attested, verified or activated;
  the student has no login, aliases or relationship to a real student.
- Existing active questions and cards are read/locked only. The card-order case
  attempts `SET updated_at = updated_at` inside an explicit transaction; the
  immutable-card trigger is expected to reject it, and the transaction is
  rolled back even if that assertion fails.
- `finally` deletes by the exact release/student UUIDs, then asserts zero rows
  remain in the student, plan, session, step, release-item, question and release
  tables. No prefix-wide or date-wide delete is used.

## Run

PowerShell:

```powershell
$env:LIVE_JUNIOR_DATABASE_URL = 'postgresql://postgres:REDACTED@db.PROJECT.supabase.co:5432/postgres'
$env:LIVE_JUNIOR_TEST_CONFIRMATION = 'CREATE_AND_DELETE_EPHEMERAL_JUNIOR_ROWS'
node supabase/tests/live_junior_concurrency.mjs
```

The script pins and caches `pg@8.23.0` under the operating-system temporary
directory if the driver is not already installed. That download and the four
TLS connection handshakes are outside the measured database acceptance budget.
The preflight, fixture setup, four contention cases and postconditions must
finish in under 10 seconds; every statement also has a 3.5-second timeout.

## Required result

The command exits zero and prints a JSON result with `"result": "pass"`, a
database-work duration below 10,000 ms, and four observed PostgreSQL lock wait
events. It then prints `cleanup=verified_zero_residue`.

The conflict outcomes are intentional and prove serialization:

| Case | Second session after the first commits |
| --- | --- |
| Stage vs. seal | Seal succeeds, server manifest is 64 hex characters, ledger count is 21 |
| Same sequence issued twice | Fails with SQLSTATE `40001` and `junior issue sequence is stale`; exactly one step exists |
| Same step answered twice | Fails with `junior session step is already locked`; exactly one answer exists |
| Formal issue vs. bound-card update | Update waits behind the advisory lock, then fails with the immutable-card error |

Any SQLSTATE `40P01` is an immediate test failure. A second session that settles
without first appearing as `wait_event_type='Lock'` is also a failure, so a fast
but non-serialized false positive cannot pass.

## Recovery after forced termination

The run token is printed before any row is created. `finally` handles ordinary
errors, Ctrl+C and termination signals. If the process is forcibly killed, use:

```powershell
$env:LIVE_JUNIOR_DATABASE_URL = 'postgresql://postgres:REDACTED@db.PROJECT.supabase.co:5432/postgres'
$env:LIVE_JUNIOR_TEST_CONFIRMATION = 'CREATE_AND_DELETE_EPHEMERAL_JUNIOR_ROWS'
node supabase/tests/live_junior_concurrency.mjs --cleanup-run PRINTED_32_HEX_TOKEN
```

Cleanup reconstructs the same four UUIDs from that token, removes only those
rows and runs the same zero-residue assertion.
