# Part 3 — Decision Log

_Pipeline Design_

## Key decisions (and why)

- **Idempotency by deterministic addressing, not by a processed-batches table.** Partition
  paths keyed on `(brand, logical_date)` plus `MERGE` on the natural key. A state table can
  desynchronise from reality and then there are two sources of truth about what happened;
  a deterministic path cannot drift.
- **Merge key is `(source_system, transaction_id)`.** Part 1 DQ-05 found 59 ids reused
  across systems. Merging on `transaction_id` alone would have been idempotent *and wrong*
  — silently discarding real transactions in order to achieve it.
- **The DQ gate is a task that publication depends on.** A check that runs beside the
  pipeline and reports to a dashboard is not a control; by the time anyone reads it the
  model has already scored on the data.
- **Two severities only — blocking and warning.** Three or more tiers get argued about and
  then ignored. The binary forces the real question for every check: *would I rather serve
  yesterday's features than today's?*
- **Per-brand fan-out and per-brand gating.** One late brand holding back nineteen healthy
  ones is a self-inflicted outage.
- **Schema drift classified, not just detected.** Halting on an additive change trains
  people to mute the channel; continuing through a breaking change corrupts the store
  silently. Both are avoidable by separating them.
- **Tokenise between raw and staging.** Anywhere later leaves a window where clear-text PII
  is queryable by every analyst — which is precisely the state Part 1 found.
- **Every DQ check names the Part 1 finding that motivated it.** Controls that cannot be
  traced to an observed failure tend to be theatre, and they are the first thing dropped
  when the pipeline needs to run faster.
- **Stated the scale assumption explicitly**, because "50x" is ambiguous — and then noted
  the design is driven by 20-brand multi-tenancy and the morning SLA, not by row count, so
  an order-of-magnitude error in that reading changes nothing.

## Alternatives considered and rejected

- **Streaming ingestion (Kafka / Flink).** Rejected: the consumer is a model that scores
  once a day at 07:00. Streaming would add materially to operational complexity to deliver
  freshness nobody consumes. Batch matches the actual SLA.
- **`INSERT` with a de-dup pass afterwards.** Rejected — it is exactly how Part 1's 1,936
  replayed rows got there. The window between insert and de-dup is a window where the data
  is wrong.
- **A `processed_batches` control table for idempotency.** Rejected as above; it is state
  that can lie.
- **Blocking on every check.** Rejected: alert fatigue is a real failure mode, and orphan
  transactions in particular are recoverable once the member feed lands, so blocking would
  stop good data for a fixable gap.
- **Warning-only on `feature_null_rate_stable`.** Rejected — this is Part 4's incident
  signature. A model scoring on silently-nulled features is worse than a model that did not
  run, because the output looks valid.
- **Hashing email irreversibly.** Rejected: email is the only identity-resolution key and
  DSARs arrive as email addresses. A vault token keeps the legal obligation satisfiable.
  Given DQ-12 (20 emails across multiple member_ids), a DSAR keyed on `member_id` would
  return an incomplete record while appearing to succeed.
- **Storing `birth_date` and deriving age at query time.** Rejected — that retains a direct
  identifier for no analytical benefit. The band is generated at ingest and the date is
  discarded.
- **dbt as the orchestrator.** Rejected: no scheduler, no sensors, no concept of waiting for
  a file to land. It is a complement, not an alternative, and I said so rather than listing
  it as a rival.
- **Databricks Workflows.** Rejected *conditionally*, and I named the condition rather than
  hiding it: if all compute already runs on Databricks it is the better answer. That is a
  fact about the existing estate, which I do not have.

## Where an AI suggestion was wrong / incomplete, and how I caught it

- **The first idempotency design used `transaction_id` as the merge key** — which is what
  every "how to make an ETL idempotent" answer says, and it is right in general. It is
  wrong *here*, and Part 1 is the only reason I knew: DQ-05 found 59 ids shared by
  genuinely different transactions across source systems. The generic best practice would
  have produced a pipeline that was demonstrably idempotent and quietly lossy. Caught it by
  writing the merge key against the audit findings rather than from the pattern.
- **The initial DQ check list was generic** — nulls, row counts, freshness — and would have
  passed every single Part 1 defect. Rewrote it so each check names the finding it exists
  to catch, which immediately exposed the gaps: nothing was checking value plausibility
  (DQ-02's sentinels), enum conformance (DQ-10), or earn-rate consistency.
- **`volume_not_zero` was the first volume check I wrote.** Nearly shipped it alone. It
  catches a total failure — the easy case, which is also the loud, obvious case. It misses
  the partial load, which is the dangerous one because a 60%-complete brand looks exactly
  like a real business drop. Added the banded check against the trailing same-weekday
  median. That check is what makes Part 4's incident a day-one detection instead of a
  Monday-morning Slack question.
- **Nearly wrote "use Airflow, or Databricks Workflows, or Dagster depending on your
  needs."** That is the non-answer the brief explicitly warns against. Committed to Airflow,
  gave four reasons specific to *this* problem, stated its real operational cost, and named
  the single condition under which the answer flips.
