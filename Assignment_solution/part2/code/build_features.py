"""Part 2 runner: build the member-level churn feature table.

Executes common/clean.sql then part2/code/features.sql, exports the feature
table and its validation views to part2/output/.

    .venv/bin/python Assignment_solution/part2/code/build_features.py
"""

import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

import duckdb  # noqa: E402

from common import paths  # noqa: E402

CLEAN_SQL = paths.SOLUTION_ROOT / "common" / "clean.sql"
FEATURES_SQL = Path(__file__).with_name("features.sql")
OUT = paths.output_dir(2)

REPORTS = [
    ("Cleaning audit (common/clean.sql)", "clean_audit"),
    ("Earn rate per brand", "brand_rate"),
    ("LEAKAGE CHECK", "leakage_check"),
    ("Label balance", "label_balance"),
    ("Churn rate by recency band (label sanity)", "churn_by_recency"),
    ("Churn rate by tier", "churn_by_tier"),
    ("Features with NULLs (by design)", "feature_nulls"),
    ("IS A 90-DAY WINDOW APPROPRIATE HERE?", "label_window_sanity"),
]


def main() -> None:
    os.chdir(paths.DATA_ROOT)
    con = duckdb.connect()
    con.execute(CLEAN_SQL.read_text())
    con.execute(FEATURES_SQL.read_text())

    lines: list[str] = []
    for title, rel in REPORTS:
        df = con.execute(f"SELECT * FROM {rel}").df()
        block = f"\n{'=' * 78}\n{title}\n{'=' * 78}\n{df.to_string(index=False)}"
        print(block)
        lines.append(block)

    feats = con.execute("SELECT * FROM member_features").df()
    feats.to_csv(OUT / "member_features.csv", index=False)

    # Feature dictionary with distributions, so the table can be reviewed without
    # loading it: dtype, null rate, and range for every column.
    prof = con.execute("""
        SELECT column_name, data_type FROM information_schema.columns
        WHERE table_name = 'member_features' ORDER BY ordinal_position
    """).df()
    stats = []
    for col, dtype in zip(prof.column_name, prof.data_type):
        if dtype in ("VARCHAR", "DATE"):
            row = con.execute(f"""
                SELECT count(*) FILTER (WHERE "{col}" IS NULL) AS nulls,
                       count(DISTINCT "{col}") AS distinct_vals,
                       NULL AS min_v, NULL AS max_v, NULL AS mean_v
                FROM member_features""").fetchone()
        else:
            row = con.execute(f"""
                SELECT count(*) FILTER (WHERE "{col}" IS NULL) AS nulls,
                       count(DISTINCT "{col}") AS distinct_vals,
                       min("{col}"), max("{col}"), round(avg("{col}"), 3)
                FROM member_features""").fetchone()
        stats.append((col, dtype, *row))

    import pandas as pd

    dic = pd.DataFrame(stats, columns=["feature", "dtype", "nulls", "distinct", "min", "max", "mean"])
    dic["null_pct"] = (100 * dic.nulls / len(feats)).round(2)
    dic.to_csv(OUT / "feature_dictionary.csv", index=False)

    # Point-biserial correlation of every numeric feature with the label. Not a
    # model, just evidence the table carries signal and a check for anything
    # suspiciously strong (which usually means leakage).
    numeric = [c for c, d in zip(prof.column_name, prof.data_type)
               if d not in ("VARCHAR", "DATE") and c != "churned_90d"]
    sel = ", ".join(f'round(corr("{c}", churned_90d), 4) AS "{c}"' for c in numeric)
    sig = con.execute(f"SELECT {sel} FROM member_features").df().T
    sig.columns = ["corr_with_churn"]
    sig = sig.reindex(sig.corr_with_churn.abs().sort_values(ascending=False).index)
    sig.index.name = "feature"
    sig.to_csv(OUT / "feature_signal.csv")

    for rel in ["clean_audit", "brand_rate", "leakage_check", "label_balance",
                "churn_by_recency", "churn_by_tier", "feature_nulls",
                "label_window_sanity"]:
        con.execute(f"SELECT * FROM {rel}").df().to_csv(OUT / f"{rel}.csv", index=False)

    con.execute(f"COPY (SELECT * FROM clean_rejects) TO '{OUT / 'quarantined_orphan_tx.csv'}' (HEADER)")

    (OUT / "build_summary.txt").write_text(
        "Part 2 — Member-level churn feature table\n" + "\n".join(lines) +
        f"\n\nmember_features.csv: {len(feats):,} members x {len(feats.columns)} columns\n"
    )
    print(f"\nmember_features.csv: {len(feats):,} members x {len(feats.columns)} columns -> {OUT}")


if __name__ == "__main__":
    main()
