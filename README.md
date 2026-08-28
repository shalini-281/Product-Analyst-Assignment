# Capillary — Product Analyst Assignment

Response to [`Product_Analyst_Assignment.md`](Product_Analyst_Assignment.md).
All analysis is SQL (DuckDB) over the two raw CSVs; Python is used only to run it.

**➡️ Start here: [`SOLUTION.md`](SOLUTION.md)** — the complete response, ~2,900 words,
with links to the detailed working for each part.

**➡️ Detail per part: [`Assignment_solution/`](Assignment_solution/)** — one folder per part,
each with the full write-up, its code, its generated evidence, and a decision log.

## Run it

```bash
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt

.venv/bin/python Assignment_solution/part1/code/run_audit.py        # data quality audit
.venv/bin/python Assignment_solution/part2/code/build_features.py   # churn feature table
.venv/bin/python Assignment_solution/part6/code/run_generosity.py   # brand generosity
.venv/bin/python Assignment_solution/part7/code/run_winback.py      # win-back list
.venv/bin/python Assignment_solution/part8/code/run_liability.py    # points liability
```

Everything regenerates from `members.csv` and `transactions.csv` in about 8 seconds.
The raw files are never modified. Parts 3–5 are design/writing and have no code.

## The parts

| Part | | Headline |
|---|---|---|
| **1** | [Data Quality & Governance Audit](Assignment_solution/part1/) | 13 findings. `status` — the column that looks like a ready-made churn label — separates active from churned by **0.7pp** and is behaviourally meaningless |
| **2** | [Feature Engineering](Assignment_solution/part2/) | 31,690 members × 37 features, leakage-checked. **A 90-day churn window is wrong for this population** — the median member buys every 204 days, so 90.8% of "churned" members are merely mid-gap |
| **3** | [Pipeline Design](Assignment_solution/part3/) | Daily, 20 brands. Idempotency by deterministic addressing; merge key `(source_system, transaction_id)` because ids are reused across systems |
| **4** | [Production Incident](Assignment_solution/part4/) | Don't escalate. Four signature properties say data failure, not behaviour — and `COALESCE(activity, 0)` is itself the bug |
| **5** | [Stakeholder Communication](Assignment_solution/part5/) | [144-word Slack message](Assignment_solution/part5/slack_message.md), written to survive being forwarded to a client |
| **6** | [Brand Generosity](Assignment_solution/part6/) | Marketing is wrong. **PulseMart 2.30 / PulseHome 2.00 / PulseEats 1.75** — and 15 corrupt rows invert the ranking, making the most generous brand look like the least |
| **7** | [Win-back List](Assignment_solution/part7/) | 20 members at **6.3× base spend**, selected on deviation from each member's *own* rhythm rather than a fixed threshold |
| **8** | [Points Liability](Assignment_solution/part8/) | **$57,900** (range $35K–$116K). 63% of members have never redeemed a point, holding 54.3% of the liability |

## Layout

```
members.csv, transactions.csv     raw exports, untouched
Assignment_solution/
  common/                         paths.py + clean.sql (shared cleaning layer)
  part1/ … part8/
    README.md                     the written answer
    decision_log.md               decisions · rejected alternatives · AI mistakes caught
    code/                         SQL + thin Python runner
    output/                       generated artefacts (regenerable)
```

**Conventions.** All recency and churn logic anchors to the data's own last transaction date
(`2026-06-30`), not the wall clock, so every number reproduces on any future run. Part 1
audits the *raw* data; `common/clean.sql` implements the fixes it prescribes, once, so
Parts 2 and 6–8 share one definition of "clean".
