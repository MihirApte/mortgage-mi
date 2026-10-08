# Data profile: Central Bank of Ireland mortgage arrears open data

Profiled on 5 October 2026 before any transformation. Every number below was measured from the file or from the raw table, not estimated. Day 2 turns each defect into a logged data quality rule.

## Source

- Publisher: Central Bank of Ireland. Dataset: Residential Mortgage Arrears and Repossession Statistics.
- Listing: https://data.gov.ie/dataset/residential-mortgage-arrears-and-repossession-statistics
- File: moa-open-data.csv, 2,367,862 bytes, SHA-256 67b8ac6b677928f8a73d90a5a3bfee77c7e0a4bd707add7833bd7533ce1540ee
- Licence: Creative Commons Attribution 4.0. Attribution to the Central Bank of Ireland is required and is given in the README.
- Publisher statement of coverage: 30 September 2009 to 31 March 2026, updated quarterly (the file used here was downloaded in October 2026).

## What the data is, and is not

It is national, quarterly, aggregate data: totals reported by lenders, split by lender group and portfolio type. It is not loan-level data. There is no loan ID, borrower, county or interest rate. This shapes every design choice: the data quality checks test the structure and arithmetic of a regulatory return, not duplicate loans. The time grain is quarterly, so the "month-on-month" idea in the brief becomes quarter-on-quarter. Monthly figures would have to be invented, and this project does not do that.

## Shape

- 19,199 data rows and 10 columns, in long format: one row is one number for one quarter, lender group, portfolio, line item and metric.
- 68 distinct reporting dates covering 67 calendar quarters from 2009 Q3 to 2026 Q1 (explained under "Reporting dates").
- Lender group: Banks and Non-Banks. Portfolio (the Format column): PDH (principal dwelling house) and BTL (buy-to-let).
- Eight categories: Arrears, Restructures - By Type, Restructures - Overview, Legal Status of Accounts in Arrears, Borrower co-operation status, Repossessions, Duration in Legal Proceedings, Total Outstanding.
- 133 distinct measures, defined by category plus row position plus column position. That combination maps to exactly one label and metric across the whole file, so it is a safe natural key.
- No fully duplicated rows, and no duplicates on the natural key (date, lender group, portfolio, category, row position, column position).

## Defects and quirks found

1. Encoding. The file is Windows-1252, not UTF-8. The euro sign is the single byte 0x80. A UTF-8 load fails. Handled in the load step by declaring the encoding.
2. One measure split across two columns. For metrics of type Number, the value sits in the padded column " Number of Accounts ". For euro metrics, it sits in Observation. The header of the account column also has leading and trailing spaces. Observation is empty in 8,297 rows and Number of Accounts is empty in 10,832 rows, and in a clean row exactly one of them is filled.
3. Numbers stored as text. 1,333 Observation values and 347 Number of Accounts values contain thousands separators (for example 1,222,625). 262 Observation values and 117 account values carry leading or trailing spaces. No value matches any other pattern, so a single cleaning rule (strip spaces, strip commas, cast to integer) covers all of them.
4. Rows where both value columns are filled: 70 rows, all in the 31 March 2026 reporting date. In those rows the Observation cell of a "Number" row holds a euro-style figure that duplicates a neighbouring row. Example for Banks PDH, 2 to 5 years in arrears: Observation 46,731, which is also the Balance figure for 5 to 10 years. The account count in the other column looks plausible. Treatment decided for Day 2: use the account column for Number rows, ignore the stray Observation, and log all 70 rows.
5. Missing totals in 31 March 2026. For Banks PDH, the Total Outstanding rows are absent, the Arrears total (row position 2) and the up to 90 days bucket (row position 3) are absent for all three metrics, and the 91 to 180 days account count is absent. That is 7 fewer Arrears rows than the other three segments, which have 24 each. Nothing is imputed. Rates that need these values show as blank for that segment and quarter, and the gap is logged.
6. Reporting dates. 21 of the 68 dates are not calendar quarter ends:
   - 19 are working-day adjusted: the last weekday of the quarter, or in three cases (28 March 2013, 29 March 2018, 28 March 2024) the Thursday before Good Friday. These map to the quarter end.
   - 2 are malformed. 01/09/2025 holds 200 rows, all euro metrics (Balance and Arrears), with zero key overlap with the 30/09/2025 rows, which hold the 176 count metrics. Together they make 376 rows, exactly the size of the 30/06/2025 quarter. So 01/09/2025 is treated as Q3 2025. 01/12/2025 holds 379 rows, a full set of metrics, and is the only candidate for Q4 2025, which would otherwise be missing. It is treated as Q4 2025. Both are inferences from the structure of the file, are logged as such, and should be confirmed against the Central Bank release if you ever need certainty.
7. Report structure changes over time (not defects, but they cause double counting or broken trends if ignored):
   - Arrears buckets: 3 buckets (up to 90, 91 to 180, over 180 days) until Q2 2012; 5 buckets until Q2 2019 (adds 181 to 365 days, 1 to 2 years, over 2 years); 7 buckets from Q3 2019 (splits over 2 years into 2 to 5, 5 to 10 and over 10 years). The schemes never overlap within one quarter.
   - Total rows ("Total mortgage accounts in arrears") equal the sum of their buckets. Example, Banks PDH 30 June 2025, account counts: 7,771 + 1,667 + 1,525 + 1,316 + 1,025 + 366 + 267 = 13,937, which matches the published total. Totals and components must never be added together.
   - Restructure types gain new categories in 2012 and 2013. Borrower co-operation status and Duration in Legal Proceedings begin in 2019.
8. Segment coverage differs: Banks and Non-Banks PDH have 68 reporting dates each, the BTL portfolios have 57.
9. Row counts per quarter range from 62 (2009) to 386 (2019 onwards), because the return grew over time. A quarter-on-quarter row-count drop is therefore a meaningful check, not noise.

## Controls used by the Day 1 checks

- 19,199 data rows (file line count minus the header, confirmed independently with pandas).
- 8,297 empty Observation cells and 10,832 empty account cells (pandas).
- A full cell-by-cell comparison of the raw table against the file found 0 differences.
