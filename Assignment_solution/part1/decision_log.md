# Part 1 — Decision Log

_Data Quality & Governance Audit_

## Key decisions (and why)

- **Read every column as `VARCHAR`.** A type-sniffing reader coerces malformed values to
  `NULL` before they can be measured — the 1,500 `MM/DD/YYYY` dates would have been
  reported as "nulls in transaction_date", hiding the real root cause behind a
  symptom with an identical row count. The parser has to be explicit and fail-closed.
- **Audit in SQL, not pandas.** Each check is a named query a reviewer can read and
  re-run; Python is a 106-line runner with no analysis logic in it. It also means Part 2
  inherits the same `parse_ts` macro and cleaning definitions instead of quietly drifting
  from the audit that justified them.
- **Applied a scope filter (MODEL / GOVERNANCE lens) rather than listing every check.**
  The brief explicitly rejects exhaustiveness. 13 findings survived; the filter itself is
  part of the answer.
- **Kept the passing checks in the output.** An audit that reports only failures gives no
  evidence of its own coverage, and it makes the whole thing re-runnable as a regression
  test.
- **Anchored time to the data's max transaction date (2026-06-30) rather than
  `current_date`.** Otherwise every number in the report silently changes depending on
  the day it is run, which is exactly the kind of thing that makes a reviewer distrust
  the rest of the submission.
- **Verified three claims before writing them down**, because each one determines a
  different fix: the duplicate split (replay vs collision), refunds vs sign errors, and
  whether the `join_date` defects were my own parser's fault. All three resolved
  decisively — and one of them inverted my initial reading.

## Alternatives considered and rejected

- **`GROUP BY transaction_id` / `SELECT DISTINCT` to deduplicate** — the reflex fix.
  Rejected once the fingerprint check showed 59 ids hold *genuinely different*
  transactions; deduplicating on id alone silently deletes 59 real events. Deduplicating
  on `(transaction_id, row_fp)` collapses only true replays.
- **Treating negative amounts as refunds and netting them off** — the intuitive reading.
  Rejected on three pieces of evidence: no clawback exists, points were computed on
  `abs(amount)`, and not one of 1,995 has a matching positive twin.
- **Dropping the 15 corrupt rows** — rejected because only `amount` is junk; the points
  are intact and the event is real. `amount = points / rate` recovers it.
- **Dropping the 1,514 null-points rows** — rejected once determinism was measured at
  100.0% within one point. Imputation is exact here, not a guess.
- **Inferring a "true" record for the 150 conflicting members** — rejected. With no
  `updated_at`, any rule is arbitrary dressed as principled. Deterministic pick + a flag
  is the honest version.
- **`initcap()` for tier normalisation** — rejected in favour of an explicit `CASE`. A
  novel value like `'Diamnod'` would be silently title-cased into a plausible-looking
  category; `CASE` sends it to `'Unknown'` loudly.
- **Adding a severity column to the report table** — rejected. The brief specifies five
  columns; rank is conveyed through row order instead.

## Where an AI suggestion was wrong / incomplete, and how I caught it

- **The corrupt-batch detector conflated two unrelated populations.** My first version
  flagged `amount > 10000 OR NOT regexp_matches(transaction_id, '^T[0-9]+$')`, assuming
  an odd id prefix marked the same bad batch. It returned **3,003 rows instead of ~15**.
  Caught it because the count was two orders of magnitude off what the amount rule alone
  could produce — so I printed the rows and found the 2,988 orphans carry a `TX` prefix
  and are a *separate* finding. Fixed by keying the detector on magnitude alone and
  promoting the prefix signal to its own evidence table, `ev_id_prefix_families` — where
  it turned out to be the strongest evidence in the audit, showing three loaders with
  perfectly homogeneous defect profiles. **The bug produced a better finding than the
  correct version would have.**
- **The determinism check understated itself and nearly cost a correct fix.** Exact-match
  came back at 98.98% for PulseHome, and I was about to write up "mostly deterministic,
  so impute cautiously". The gap is a **rounding convention**: at PulseHome's rate of
  exactly 2.0, `rate × amount` lands on `.5` constantly, and DuckDB rounds half away from
  zero where the source rounds half to even. Caught it by noticing the *worst* match rate
  belonged to the brand with the *cleanest* rate — the opposite of what real
  non-determinism would look like. Measuring within-1-point gives **100.0%**. That is the
  difference between dropping 1,514 rows and imputing them exactly.
- **First instinct on the slash dates was "ambiguous, flag and move on."** Wrong — the
  orientation is decidable from the data: component 1 never exceeds 12 while component 2
  reaches 31, so only `MM/DD` fits. Worth checking rather than caveating, because
  guessing `dayfirst` would have produced 950 silently wrong months.
- **`status` was nearly taken at face value.** It is the most churn-shaped column in the
  file and the obvious label. Testing it against behaviour instead of assuming took one
  query and overturned the entire modelling approach in Part 2.
