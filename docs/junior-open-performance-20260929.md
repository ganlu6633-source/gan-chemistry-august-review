# Junior lesson opening latency — 2026-09-29

The reported first-open request took 9,836 ms in Edge v74. It executed in Tokyo
and made 19 database API requests, including repeated program/profile/plan reads.
This release reduces those round trips and routes junior requests near the database.

## Changes

- Parallelize owned plan/profile/session reads; enforce the same program, textbook,
  unit, future-access and immutable-session gates before issuing content.
- Read option state alongside independent card/history reads; overlap pending
  question lookup with atomic validation, awaiting both before returning content.
- Limit junior ready-question checks to the requested IDs. Keep every existing
  source/release/item-review/hold predicate and retain the original view for other grades.
- Route old clients through one fixed, trusted same-project Sydney invocation.
  Supabase rewrites the incoming URL to HTTP inside the worker, so inbound origin
  is not used as a destination or identity check. Authentication remains in the
  destination handler; only the deployment configuration determines the target.
- Preserve exact answer request bytes. Never relay twice, retry authorization
  errors or cancellation, or redirect an explicitly selected fallback region.
- Fix an additional opening defect found during testing: explicitly authorized
  future lessons must not fail the immutable contract solely because of the date.

## Online checks

Edge v77 and migration `junior_targeted_ready_lookup` were deployed. Tests used
two temporary, tagged QA profiles; no answers were submitted and no real student's
learning records were modified. Normal HTTP samples include network transfer and
are not browser-render timings or production percentiles.

| Request | Before | After |
| --- | --- | --- |
| QA initial open | 7.805 s | New lesson dates: 3.203 s and 3.807 s |
| Resume, old automatic URL | 5.865 s / 4.543 s | 2.313 s / 2.370 s |
| Resume, direct Sydney | 4.527 s / 3.622 s / 3.336 s | 2.417 s / 2.034 s / 2.978 s |

**Slow sample retained:** the first automatic request immediately after deploying
v77 took 7.205 s (4.019 s server time). These changes do not establish instant
opening or eliminate cold-start/network outliers. Subsequent server times were
0.833–1.020 s for direct resumes and 1.639–1.905 s for first opens.

The pending question's step and snapshot stayed identical across v74/v75/v77.
The first question renders while unrelated catalog/dashboard reads are unresolved,
in both the student UI and teacher simulation.

## Database and regression verification

- All 671 junior IDs: old view and new function both return 289 ready questions;
  bidirectional difference is empty. High-school samples of 120 IDs per grade also
  match exactly (85 / 97 / 113 ready).
- Only `postgres` and `service_role` retain execution permission. The function
  remains stable, security-definer, with an empty search path.
- Single-question SQL time measured 450.8 ms before, 74.1 ms after deployment;
  an 83-question check measured 523.0 ms before, 129.6 ms after. Single samples
  fluctuate; these are database timings, not end-to-end timings.
- Regional transport, future access, pending-answer recovery, daily 8/30/3 policy,
  source gates, calendar access and first-question independence are covered by
  regression tests. TypeScript, Deno checking and production build pass.
- Existing static assets remain available so already-open tabs can still load
  their matching chunks.

A more complex practice-pool SQL candidate was investigated but was not deployed;
it needs separate failure-injection tests before replacing the existing graph rules.
