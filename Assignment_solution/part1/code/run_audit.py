"""Part 1 runner.

Executes audit.sql against the raw CSVs and exports every evidence table to
part1/output/. Deliberately thin: all analysis lives in SQL so the audit is
readable and re-runnable by anyone with DuckDB, with or without this script.

    ../.venv/bin/python part1/code/run_audit.py
"""

import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

import duckdb  # noqa: E402

from common import paths  # noqa: E402

SQL_FILE = Path(__file__).with_name("audit.sql")
OUT = paths.output_dir(1)

# Exported in report order: the consolidated findings first, then the detail
# each finding rests on.
EXPORTS = [
    "dq_findings",
    "ev_status_vs_behaviour",
    "ev_corrupt_batch",
    "ev_id_prefix_families",
    "ev_member_key_integrity",
    "ev_member_conflict_fields",
    "ev_member_conflict_sample",
    "ev_tx_key_integrity",
    "ev_tx_collision_sample",
    "ev_orphan_transactions",
    "ev_points_rate_by_brand",
    "ev_points_determinism",
    "ev_negative_amount_diagnosis",
    "ev_negative_refund_pairing",
    "ev_date_formats",
    "ev_slash_date_orientation",
    "ev_join_date_defects",
    "ev_tier_variants",
    "ev_country_variants",
    "ev_identity_and_pii",
    "ev_null_points",
    "ev_brand_agreement",
    "ev_checks_passed",
]

# Printed to the console and to audit_summary.txt, since these are the tables the
# written report quotes directly.
HEADLINE = [
    ("Consolidated findings", "dq_findings"),
    ("DQ-01  status vs actual behaviour", "ev_status_vs_behaviour"),
    ("DQ-02  corrupted batch (all rows)", "ev_corrupt_batch"),
    ("DQ-02  transaction_id families", "ev_id_prefix_families"),
    ("DQ-03  member key integrity", "ev_member_key_integrity"),
    ("DQ-03  which fields disagree", "ev_member_conflict_fields"),
    ("DQ-04/05  transaction key integrity", "ev_tx_key_integrity"),
    ("DQ-06  orphan transactions", "ev_orphan_transactions"),
    ("DQ-06  earn rate by brand", "ev_points_rate_by_brand"),
    ("DQ-06  are points deterministic?", "ev_points_determinism"),
    ("DQ-07  negative amounts: refund or sign error?", "ev_negative_amount_diagnosis"),
    ("DQ-07  refund pairing test", "ev_negative_refund_pairing"),
    ("DQ-08  date formats", "ev_date_formats"),
    ("DQ-08  slash-date orientation proof", "ev_slash_date_orientation"),
    ("DQ-09  join_date defects", "ev_join_date_defects"),
    ("DQ-10  tier variants", "ev_tier_variants"),
    ("DQ-10  country variants", "ev_country_variants"),
    ("DQ-11  null points", "ev_null_points"),
    ("DQ-12/13  identity + PII", "ev_identity_and_pii"),
    ("Context  transaction brand vs member brand", "ev_brand_agreement"),
    ("Checks that PASSED", "ev_checks_passed"),
]


def main() -> None:
    # audit.sql reads 'members.csv' / 'transactions.csv' by relative path so it
    # also runs standalone under `duckdb < audit.sql`.
    os.chdir(paths.DATA_ROOT)

    con = duckdb.connect()
    con.execute(SQL_FILE.read_text())

    lines: list[str] = []
    for title, rel in HEADLINE:
        df = con.execute(f"SELECT * FROM {rel}").df()
        block = f"\n{'=' * 78}\n{title}\n{'=' * 78}\n{df.to_string(index=False)}"
        print(block)
        lines.append(block)

    for rel in EXPORTS:
        con.execute(f"SELECT * FROM {rel}").df().to_csv(OUT / f"{rel}.csv", index=False)

    (OUT / "audit_summary.txt").write_text(
        "Part 1 — Data Quality & Governance Audit\n"
        f"Generated from {SQL_FILE.name} against {paths.MEMBERS_CSV.name} "
        f"and {paths.TRANSACTIONS_CSV.name}\n" + "\n".join(lines) + "\n"
    )

    print(f"\n{len(EXPORTS)} evidence tables + audit_summary.txt written to {OUT}")


if __name__ == "__main__":
    main()
