"""Shared path resolution so every part's code runs from any working directory.

The raw CSVs live at the project root, one level above `Assignment_solution/`.
Rather than hard-coding how deep we are, walk upwards until we find the data.
"""
from pathlib import Path

SOLUTION_ROOT = Path(__file__).resolve().parents[1]


def _find_data_root(start: Path) -> Path:
    for candidate in [start, *start.parents]:
        if (candidate / "members.csv").exists():
            return candidate
    raise FileNotFoundError(
        f"members.csv not found in {start} or any parent directory."
    )


DATA_ROOT = _find_data_root(SOLUTION_ROOT)

MEMBERS_CSV = DATA_ROOT / "members.csv"
TRANSACTIONS_CSV = DATA_ROOT / "transactions.csv"

# Max transaction_date observed in the raw export. Used as the "today" anchor for
# all recency / churn-window logic so results are reproducible rather than
# dependent on the real wall-clock date. Verified in Part 1 profiling.
DATA_ANCHOR_DATE = "2026-06-30"


def part_dir(part: int) -> Path:
    return SOLUTION_ROOT / f"part{part}"


def output_dir(part: int) -> Path:
    """Return (and create) the output folder for a given part."""
    d = part_dir(part) / "output"
    d.mkdir(parents=True, exist_ok=True)
    return d
