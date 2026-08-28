"""Part 7 runner: build the win-back target list."""
import os, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
import duckdb
from common import paths

OUT = paths.output_dir(7)
REPORTS = [
    ("Exclusion funnel", "wb_exclusion_funnel"),
    ("THE LIST -- 20 members", "wb_target_list"),
    ("List composition", "wb_list_composition"),
    ("Selected vs eligible pool vs whole base", "wb_list_vs_base"),
    ("Personal-rhythm rule vs fixed 90-day rule", "wb_vs_naive_rule"),
]

def main() -> None:
    os.chdir(paths.DATA_ROOT)
    con = duckdb.connect()
    con.execute((paths.SOLUTION_ROOT / "common" / "clean.sql").read_text())
    con.execute(Path(__file__).with_name("winback.sql").read_text())
    lines = []
    for title, rel in REPORTS:
        df = con.execute(f"SELECT * FROM {rel}").df()
        block = f"\n{'='*100}\n{title}\n{'='*100}\n{df.to_string(index=False)}"
        print(block); lines.append(block)
        df.to_csv(OUT / f"{rel.replace(' ','_')}.csv", index=False)
    con.execute(f"COPY (SELECT * FROM wb_eligible) TO '{OUT/'eligible_pool.csv'}' (HEADER)")
    (OUT / "winback_summary.txt").write_text("Part 7 — Win-back list\n" + "\n".join(lines) + "\n")
    print(f"\n-> {OUT}")

if __name__ == "__main__":
    main()
