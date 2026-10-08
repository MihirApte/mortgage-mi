# Day 4: UAT test checklist

UAT means user acceptance testing: before anyone relies on the dashboard, check that what it shows equals what an independent route says it should show. Here the independent route is SQL (table dq.expected_kpi, file powerbi/data/expected_kpi.csv, produced by sql/15_expected_kpis.sql). A third check, scripts/verify_powerbi_exports.py, proved the CSV files Power BI reads match the SQL.

How to use this file: open the .pbix, set the condition in the "Set" line, read the number on the dashboard, and write it in the "Actual" line. Mark Pass if it is equal (percentages to 2 decimals, counts exactly), Fail if not. A failed test is a finding, not an embarrassment: write what you found and what you did. Leave nothing blank at the end. Do not fill any Actual line from this file. The Expected values below come from SQL, the Actual values must come from the dashboard.

Result key: Pass, Fail, Partial (some values in the test were on the dashboard and all matched, the rest were not shown) or Not run.

## Part A: Executive overview, latest complete quarter (2025 Q4)

A1. Set: no slicer selection. Check: card Reporting Quarter Label. Expected: 2025 Q4. Actual: not tested: the final pages have no Reporting Quarter Label card; the slicer and the Completeness Note both show 2025 Q4 (page 1 screenshot (docs/images/page1_executive_overview.png)). Result: Not run

A2. Check: Arrears Accounts card (all segments). Expected: 41,018. Actual: 41,018 on the Arrears accounts card (page 1 screenshot (docs/images/page1_executive_overview.png)). Result: Pass

A3. Check: Outstanding Accounts. Expected: 745,765. Actual: 745,765 in the Total row of the segment summary table (page 1 screenshot (docs/images/page1_executive_overview.png)). Result: Pass

A4. Check: Arrears Rate (Accounts). Expected: 5.50 percent. Actual: 5.50 percent on the Arrears rate (accounts) card (page 1 screenshot (docs/images/page1_executive_overview.png)). Result: Pass

A5. Check: Arrears Rate (Balance). Expected: 6.98 percent. Actual: 6.98 percent on the Arrears rate (balance) card (page 1 screenshot (docs/images/page1_executive_overview.png)). Result: Pass

A6. Check: Outstanding Balance (EUR bn). Expected: 115.4 (source 115,399,397 thousand euro). Actual: 115.4 on the Outstanding (EUR bn) card (page 1 screenshot (docs/images/page1_executive_overview.png)). Result: Pass

A7. Check: Arrears Balance (EUR bn). Expected: 8.0 (source 8,049,539 thousand euro). Actual: not tested: no Arrears Balance card on the final pages. Result: Not run

A8. Check: Arrears Amount (EUR m). Expected: 3,335.2 (source 3,335,190 thousand euro). Actual: not tested: no Arrears Amount card on the final pages. Result: Not run

A9. Check: QoQ Change Arrears Accounts. Expected: minus 1,389. Actual: minus 1,389 on the Change vs previous quarter card (page 1 screenshot (docs/images/page1_executive_overview.png)). Result: Pass

A10. Check: QoQ Change Arrears Rate (pp). Expected: minus 0.17. Actual: minus 0.17 in the Total row of the segment risk table (page 2 screenshot (docs/images/page2_risk_and_arrears.png)). Result: Pass

A11. Check: QoQ Change Outstanding Balance. Expected: plus 1,217,227 thousand euro. Actual: not tested: no QoQ Change Outstanding Balance visual on the final pages. Result: Not run

A12. Check: Completeness Note. Expected: "2025 Q4: 4 of 4 segments reported." Actual: "2025 Q4: 4 of 4 segments reported." in the Completeness check strip (page 1 screenshot (docs/images/page1_executive_overview.png)). Result: Pass

## Part B: Segment figures, 2025 Q4

Expected values (arrears accounts, outstanding accounts, arrears rate by accounts, over 180 days share, risk rank, QoQ change in arrears accounts):

- Banks BTL: 1,016; 29,226; 3.48 percent; 47.64 percent; rank 3; minus 263.
- Banks PDH: 13,421; 594,624; 2.26 percent; 28.57 percent; rank 4; minus 32.
- Non-Banks BTL: 4,770; 18,094; 26.36 percent; 80.23 percent; rank 1; minus 252.
- Non-Banks PDH: 21,811; 103,821; 21.01 percent; 69.52 percent; rank 2; minus 842.

B1. Check: segment table, Banks BTL row, all six values. Actual: Banks BTL: 1,016; 29,226; 3.48 percent; 47.6 percent; rank 3 all match. The QoQ change in accounts (minus 263) is not displayed on the final pages (page 1 screenshot (docs/images/page1_executive_overview.png), page 2 screenshot (docs/images/page2_risk_and_arrears.png)). Result: Partial: 5 of 6 values checked, all match

B2. Check: Banks PDH row. Actual: Banks PDH: 13,421; 594,624; 2.26 percent; 28.6 percent; rank 4 all match. The QoQ change in accounts (minus 32) is not displayed. Result: Partial: 5 of 6 values checked, all match

B3. Check: Non-Banks BTL row. Actual: Non-Banks BTL: 4,770; 18,094; 26.36 percent; 80.2 percent; rank 1 all match. The QoQ change in accounts (minus 252) is not displayed. Result: Partial: 5 of 6 values checked, all match

B4. Check: Non-Banks PDH row. Actual: Non-Banks PDH: 21,811; 103,821; 21.01 percent; 69.5 percent; rank 2 all match. The QoQ change in accounts (minus 842) is not displayed. Result: Partial: 5 of 6 values checked, all match

B5. Check: the Highest Risk Segment card. Expected: Non-Banks BTL. Actual: Non-Banks BTL on the Highest risk segment card (page 2 screenshot (docs/images/page2_risk_and_arrears.png)). Result: Pass

B6. Check: the Total row of the table has no rank. Expected: blank. Actual: the Total row rank is blank in both segment tables (page 1 screenshot (docs/images/page1_executive_overview.png), page 2 screenshot (docs/images/page2_risk_and_arrears.png)). Result: Pass

## Part C: Arrears age buckets, 2025 Q4

Expected accounts (up to 90 days, 91 to 180 days, over 180 days):

- All segments: 14,569; 3,139; 23,310. These add to 41,018.
- Banks BTL: 445; 87; 484.
- Banks PDH: 8,057; 1,529; 3,835.
- Non-Banks BTL: 725; 218; 3,827.
- Non-Banks PDH: 5,342; 1,305; 15,164.

C1. Check: bucket chart, all segments, three values. Actual: not tested: the bucket chart in the final screenshot shows an earlier range of quarters and no readable 2025 Q4 values. Result: Not run

C2. Check: the three buckets add to the Arrears Accounts card (41,018). Actual sum: not tested. Result: Not run

C3. Check: select Non-Banks PDH in a segment slicer, read the three buckets. Actual: not tested: needs a slicer selection that is not in the screenshots. Result: Not run

## Part D: Trend

D1. Check: the market arrears rate line (Arrears Rate Market Trend). Expected: 55 points, first at 2012 Q2 (17.80 percent), highest at 2013 Q2 (19.89 percent), last at 2025 Q4 (5.50 percent). Actual: not tested: the screenshots were taken before the quarter sort fix, so the line was out of date order. Result: Not run

D2. Check: hover over 2019 Q4, 2022 Q4, 2024 Q4 and 2025 Q3. Expected: 9.12, 7.19, 6.58 and 5.67 percent. Actual: not tested: needs hovering on the chart. Result: Not run

D3. Check: quarters before 2012 Q2 do not appear on the market line, because not all 4 segments report. Expected: no points before 2012 Q2. Actual: not tested. Result: Not run

## Part E: Incomplete quarter (2026 Q1)

E1. Set: slicer to 2026 Q1. Check: Completeness Note. Expected: "2026 Q1: 3 of 4 segments reported. Totals leave out the missing segment." Actual: not tested: the 2026 Q1 slicer selection is not in the screenshots. Result: Not run

E2. Check: Arrears Accounts card. Expected: 27,824 (990 + 4,718 + 22,116). Actual: not tested. Result: Not run

E3. Check: Banks PDH row in the segment table. Expected: blank, not zero. Actual: not tested. Result: Not run

E4. Check: QoQ Change Arrears Accounts card (all segments). Expected: blank, because 2026 Q1 and 2025 Q4 cover different segments. Actual: not tested. Result: Not run

E5. Check: QoQ change per segment. Expected: Banks BTL minus 26, Non-Banks BTL minus 52, Non-Banks PDH plus 305. Actual: not tested. Result: Not run

E6. Check: market trend line does not draw a point for 2026 Q1. Actual: not tested. Result: Not run

## Part F: Data quality page

These come from dq.check_result, dq.reconciliation and dq.issue_log after the full pipeline run.

F1. Check: DQ Rules Run. Expected: 23. Actual: 23 on the Rules run card (page 3 screenshot (docs/images/page3_data_quality.png)). Result: Pass

F2. Check: DQ Rules Passed. Expected: 18. Actual: 18 on the Rules passed card (page 3 screenshot (docs/images/page3_data_quality.png)). Result: Pass

F3. Check: DQ Rules Warning. Expected: 4 (DQ02, DQ06, DQ16, DQ21). Actual: 4 on the Rules with warning card (page 3 screenshot (docs/images/page3_data_quality.png)). Result: Pass

F4. Check: DQ Rules Info. Expected: 1 (DQ23). Actual: 1 on the Rules info only card (page 3 screenshot (docs/images/page3_data_quality.png)). Result: Pass

F5. Check: DQ Rules Failed. Expected: 0. Actual: 0 on the Rules failed card (page 3 screenshot (docs/images/page3_data_quality.png)). Result: Pass

F6. Check: Reconciliation Steps and Reconciliation Matched. Expected: 102 and 102. Actual: 102 on the Reconciliation steps matched card (page 3 screenshot (docs/images/page3_data_quality.png)). The steps total is not shown on the page because totals are off; the SQL count of steps is 102. Result: Partial: matched count checked

F7. Check: Issues Logged. Expected: 11. Actual: not tested: the Issue log table in the screenshot is scrolled and does not show all rows. Result: Not run

F8. Check: rows failed on the four warnings. Expected: DQ02 70, DQ06 5,935, DQ16 2, DQ21 5. Actual: not tested: the Rows failed column is cut off in the screenshot. Result: Not run

Note on the measure Issue Rows Affected: it adds the rows_affected of all 11 issues and gives 38,339, which is more than the 19,199 rows in the file, because one row can be affected by several issues. Do not show it as a headline number. Show each issue with its own count instead.

## Part G: Lineage spot checks

G1. Pick any value in the fact file, for example the first row of powerbi/data/fact_mortgage_measure.csv, take its source_raw_row_id, and find that row in the raw file. Expected: the value (after removing commas, and picking the right value column) matches. Actual: the first row of powerbi/data/fact_mortgage_measure.csv has source_raw_row_id 12 and value 56,868 (30 Sep 2009, Banks PDH, arrears accounts). Raw row 12 reads 30/09/2009, Banks, PDH, Arrears: Total mortgage accounts in arrears, 56868. Equal. Result: Pass

G2. Check: Part A to C numbers also equal the SQL answer key rows in powerbi/data/expected_kpi.csv for quarter 2025 Q4. Actual: 16 key values from Parts A to C (totals, rates, buckets, segment arrears accounts, QoQ changes) equal the 2025 Q4 rows of powerbi/data/expected_kpi.csv, and scripts/verify_powerbi_exports.py prints PASSED: 34 comparisons. Result: Pass

## Outcome record

Date tested: 8 October 2026. Dashboard values were read from the final page screenshots in docs/images. Checks against the SQL answer key and the raw file (G1, G2) were run directly.
Tester: Mihir Apte, with the screenshot review and SQL checks carried out by Claude.
Tests passed: 17 of 40 Pass, 5 Partial (every value that could be checked matched), 18 Not run, 0 Fail.
Failures and what was done about each: none found in the checks that were run. During the build, three issues were found and fixed before the final screenshots: a false minus 13 thousand quarter on quarter change when a segment was missing (fixed with the Like For Like check), a trend line showing a single point (fixed with Edit interactions set to None), and quarters sorted by value on the two trend charts (fixed by sorting on quarter). The Not run tests need a slicer change or a hover, for example 2026 Q1 (Part E), the age bucket values (Part C) and the trend line points (Part D). They are not claimed as passed.
Known limitation accepted: the data is aggregate, not loan level, and has no PTSB figures.
