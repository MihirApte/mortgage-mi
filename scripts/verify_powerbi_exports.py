"""
verify_powerbi_exports.py
Purpose : Recompute the headline KPIs for the latest complete quarter straight from the exported
          CSV files in powerbi/data, using only the Python standard library, and compare them with
          the answer key powerbi/data/expected_kpi.csv.

This is the same join Power BI performs (fact to dimensions), done by a third tool. If this script
agrees with the SQL answer key, the CSV files are a faithful copy of the mart, and any later
difference on the dashboard must come from the DAX or the report, not from the data.

Run from the repository root:  python scripts/verify_powerbi_exports.py
"""
import csv
import sys
from collections import defaultdict

DATA = "powerbi/data/"


def read(name):
    with open(DATA + name, newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def main():
    dates = {r["date_key"]: r for r in read("dim_date.csv")}
    segments = {r["segment_key"]: r["segment_label"] for r in read("dim_segment.csv")}
    measures = {r["measure_key"]: r for r in read("dim_measure.csv")}
    latest = [r for r in dates.values() if r["is_latest_complete_quarter"] == "true"]
    if len(latest) != 1:
        print("FAIL: expected exactly one latest complete quarter, found", len(latest))
        return 1
    quarter = latest[0]["quarter_label"]
    latest_key = latest[0]["date_key"]

    totals = defaultdict(int)
    for row in read("fact_mortgage_measure.csv"):
        if row["date_key"] != latest_key:
            continue
        measure = measures[row["measure_key"]]
        seg = segments[row["segment_key"]]
        value = int(row["value"])
        code = measure["measure_code"]
        if code:
            totals[(seg, code)] += value
        if measure["category"] == "Arrears" and measure["metric_name"] == "Accounts" and measure["harmonised_bucket"] == "Over 180 days":
            totals[(seg, "OVER_180")] += value

    answer = {}
    for row in read("expected_kpi.csv"):
        if row["quarter_label"] == quarter and row["kpi_value"] != "":
            answer[(row["segment"], row["kpi_code"])] = float(row["kpi_value"])

    mapping = {
        "ARREARS_ACCOUNTS": "arrears_accounts",
        "OUTSTANDING_ACCOUNTS": "outstanding_accounts",
        "ARREARS_BALANCE": "arrears_balance",
        "OUTSTANDING_BALANCE": "outstanding_balance",
        "ARREARS_AMOUNT": "arrears_amount",
        "OVER_180": "over_180_accounts",
    }
    failures = 0
    checked = 0
    for seg in sorted(set(s for s, _ in totals)):
        for code, kpi in mapping.items():
            mine = totals[(seg, code)]
            theirs = answer.get((seg, kpi))
            checked += 1
            if theirs is None or abs(mine - theirs) > 0.5:
                failures += 1
                print("MISMATCH", quarter, seg, kpi, "csv", mine, "sql", theirs)
        rate = totals[(seg, "ARREARS_ACCOUNTS")] / totals[(seg, "OUTSTANDING_ACCOUNTS")]
        checked += 1
        if abs(rate - answer[(seg, "arrears_rate_accounts")]) > 1e-9:
            failures += 1
            print("MISMATCH", quarter, seg, "arrears_rate_accounts", rate, answer[(seg, "arrears_rate_accounts")])
    for code, kpi in mapping.items():
        mine = sum(totals[(s, code)] for s in segments.values())
        theirs = answer.get(("All segments", kpi))
        checked += 1
        if theirs is None or abs(mine - theirs) > 0.5:
            failures += 1
            print("MISMATCH", quarter, "All segments", kpi, "csv", mine, "sql", theirs)

    if failures:
        print("FAILED:", failures, "of", checked, "comparisons differ")
        return 1
    print("PASSED: %d comparisons for %s agree between the CSV files and the SQL answer key" % (checked, quarter))
    return 0


if __name__ == "__main__":
    sys.exit(main())
