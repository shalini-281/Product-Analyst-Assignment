# Capillary — Product Analyst Assignment

Response to `Product_Analyst_Assignment.md`. One folder per part; each part holds its
own code, its own generated output, and its own decision log.

## Layout

```
members.csv, transactions.csv     raw exports (untouched)
common/                           paths.py + clean.sql (shared cleaning layer)
part1/ ... part8/
  ├── README.md                   the written answer for that part
  ├── decision_log.md             decisions, rejected alternatives, AI mistakes caught
  ├── code/                       scripts that produce the output
  └── output/                     generated artefacts (regenerable; do not hand-edit)
```

| Part | Section | Title | Status |
|---|---|---|---|
| 1 | Pipeline & Modelling | Data Quality & Governance Audit | **Complete** |
| 2 | Pipeline & Modelling | Feature Engineering for a Churn Model | **Complete** |
| 3 | Pipeline & Modelling | Pipeline Design | **Complete** |
| 4 | Pipeline & Modelling | Production Incident | **Complete** |
| 5 | Pipeline & Modelling | Stakeholder Communication | **Complete** |
| 6 | Analytical Reasoning | Which brand is actually the most generous? | **Complete** |
| 7 | Analytical Reasoning | Pick the win-back campaign list | **Complete** |
| 8 | Analytical Reasoning | What's the outstanding points liability? | **Complete** |

## Running the code

```bash
../.venv/bin/python part1/code/<script>.py
```

Environment: Python 3.14 venv at `.venv/` with `pandas` and `duckdb`.
Recreate with:

```bash
python3 -m venv .venv && .venv/bin/pip install pandas duckdb
```

## Conventions

- **Time anchor:** the raw data ends `2026-06-30`. All recency and churn-window logic
  anchors to that date (`common.paths.DATA_ANCHOR_DATE`) rather than the wall clock,
  so every number here is reproducible.
- Raw CSVs are never modified in place; every script reads raw and writes to `output/`.
