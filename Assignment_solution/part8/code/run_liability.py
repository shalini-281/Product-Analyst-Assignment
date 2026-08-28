"""Part 8 runner: outstanding points liability."""
import os, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
import duckdb
from common import paths

OUT = paths.output_dir(8)
REPORTS = [
    ("1. Gross outstanding points", "l1_gross_points"),
    ("2. By brand", "l2_by_brand"),
    ("3. Orphan exposure (DQ-06)", "l3_orphan_exposure"),
    ("4. BREAKAGE TEST -- redemption by cohort age", "l4_cohort_burndown"),
    ("5. Redemption mechanics", "l5_redemption_mechanics"),
    ("6. Balance by dormancy", "l6_balance_by_dormancy"),
    ("6b. Members who have NEVER redeemed", "l6b_never_redeemed"),
    ("7. Point value anchored to earn rate", "l7_point_value_anchor"),
    ("8. HEADLINE liability", "l8_headline_liability"),
    ("9. SENSITIVITY -- value per point x ultimate redemption", "l9_sensitivity"),
    ("10. How much rests on Part 1 repairs", "l10_repair_exposure"),
]

def main() -> None:
    os.chdir(paths.DATA_ROOT)
    con = duckdb.connect()
    con.execute((paths.SOLUTION_ROOT / "common" / "clean.sql").read_text())
    con.execute(Path(__file__).with_name("liability.sql").read_text())
    lines = []
    for title, rel in REPORTS:
        df = con.execute(f"SELECT * FROM {rel}").df()
        block = f"\n{'='*95}\n{title}\n{'='*95}\n{df.to_string(index=False)}"
        print(block); lines.append(block)
        df.to_csv(OUT / f"{rel}.csv", index=False)
    (OUT / "liability_summary.txt").write_text("Part 8 — Points liability\n" + "\n".join(lines) + "\n")
    print(f"\n-> {OUT}")

if __name__ == "__main__":
    main()
