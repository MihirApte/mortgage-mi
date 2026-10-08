"""
independent_controls.py

Recomputes control totals straight from the source CSV with plain Python (standard library
only), without using any of the SQL cleaning logic. The results are compared with the mart in
sql/12_day2_controls.sql. Two independent implementations agreeing is stronger evidence than
one implementation checking itself.

Usage, from the repository root:
    python scripts/independent_controls.py
"""
import csv
import json
import re
from collections import Counter

SOURCE = "data/raw/moa-open-data.csv"
EURO = chr(8364)


def to_int(text):
    """Strip padding and thousands commas, return an int, or None if not purely digits."""
    if text is None:
        return None
    cleaned = text.strip().replace(",", "")
    return int(cleaned) if re.fullmatch(r"[0-9]+", cleaned) else None


def main():
    rows = 0
    value_total = 0
    stray = 0
    euro_rows = 0
    count_rows = 0
    unparsed = 0
    by_category = Counter()
    by_segment = Counter()

    with open(SOURCE, newline="", encoding="cp1252") as handle:
        reader = csv.reader(handle)
        next(reader)  # header row
        for record in reader:
            (date, entity, fmt, category, row_pos, col_pos, label, obs_type, obs, accounts) = record[:10]
            rows += 1
            if EURO in obs_type:
                expected, other = obs, accounts
                euro_rows += 1
            else:
                expected, other = accounts, obs
                count_rows += 1
            if other.strip() != "":
                stray += 1
            value = to_int(expected)
            if value is None:
                unparsed += 1
            else:
                value_total += value
            by_category[category.strip()] += 1
            by_segment[entity.strip() + " " + fmt.strip()] += 1

    result = {
        "rows": rows,
        "value_total": value_total,
        "stray_value_rows": stray,
        "euro_rows": euro_rows,
        "count_rows": count_rows,
        "unparsed_rows": unparsed,
        "rows_by_category": dict(sorted(by_category.items())),
        "rows_by_segment": dict(sorted(by_segment.items())),
    }
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
