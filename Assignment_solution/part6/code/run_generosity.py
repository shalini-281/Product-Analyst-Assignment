"""Part 6 runner: settle the brand-generosity claim."""
import os, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
import duckdb
from common import paths

OUT = paths.output_dir(6)
REPORTS = [
    ("1. NAIVE -- raw data, sum(points)/sum(amount)", "g1_naive"),
    ("2. CLEANED", "g2_clean"),
    ("3. CONTAMINATION -- ranking at each cleaning step", "g3_contamination"),
    ("4. The 15 sentinel rows and the phantom dollars they add", "g4_sentinel_impact"),
    ("5. FRAMINGS -- does any of them make PulseEats the winner?", "g5_framings"),
    ("6. Confound: earn rate by tier", "g6_tier_confound"),
    ("7. Confound: basket size", "g7_basket_confound"),
    ("8. Point utility proxy -- redemption behaviour", "g8_point_utility_proxy"),
    ("9. BREAK-EVEN -- what must be true for marketing to be right?", "g9_breakeven"),
    ("10. Weak signal on relative point value", "g10_redemption_size_signal"),
]

def main() -> None:
    os.chdir(paths.DATA_ROOT)
    con = duckdb.connect()
    con.execute((paths.SOLUTION_ROOT / "common" / "clean.sql").read_text())
    con.execute(Path(__file__).with_name("generosity.sql").read_text())
    lines = []
    for title, rel in REPORTS:
        df = con.execute(f"SELECT * FROM {rel}").df()
        block = f"\n{'='*78}\n{title}\n{'='*78}\n{df.to_string(index=False)}"
        print(block); lines.append(block)
        df.to_csv(OUT / f"{rel}.csv", index=False)
    (OUT / "generosity_summary.txt").write_text(
        "Part 6 — Brand generosity\n" + "\n".join(lines) + "\n")
    print(f"\n{len(REPORTS)} tables -> {OUT}")

if __name__ == "__main__":
    main()
