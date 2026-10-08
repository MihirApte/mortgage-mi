# Day 3: Power BI model and DAX measures

This document explains the model, every DAX measure, the checks that prove the measures right, and the exact steps to build it in Power BI Desktop. Day 4 builds the report pages on top of this model.

## 1. What was added to the pipeline today

Everything below is SQL, runs inside sql/run_all.sql and is tested like the earlier layers.

- sql/04 and sql/07: dim_measure has a new column measure_code, set only on the 5 headline measures (ARREARS_ACCOUNTS, ARREARS_BALANCE, ARREARS_AMOUNT, OUTSTANDING_ACCOUNTS, OUTSTANDING_BALANCE). DAX filters on these codes, not on label text, so a relabelled line item cannot silently change a KPI.
- sql/14_bi_views.sql: three reporting views, a thin presentation layer on top of the tested mart. v_bi_dim_segment (4 rows: Banks BTL, Banks PDH, Non-Banks BTL, Non-Banks PDH), v_bi_fact (the same 19,199 rows plus segment_key) and v_bi_dim_date (adds is_complete_quarter and is_latest_complete_quarter). The script checks that the view has the same row count and the same value total as the mart fact.
- sql/15_expected_kpis.sql: the answer key. It computes the headline KPIs in plain SQL into dq.expected_kpi, for every quarter and segment. It also proves that the 3 arrears buckets add exactly to the total in arrears in all 300 segment-quarters with data.
- sql/16_powerbi_export.sql: writes the 9 CSV files in powerbi/data.
- scripts/verify_powerbi_exports.py: a third tool (plain Python) recomputes the latest complete quarter from the CSV files and compares with the answer key: 34 comparisons agree.
- powerbi/measures.dax: all DAX measures, with comments.

## 2. Why the model looks the way it does

Why a segment dimension in the BI layer when the mart stores lender group and portfolio as two keys? To rank "top segments by risk" you need one column that names a segment. With one segment_label column, RANKX is one simple expression. The mart is unchanged. The views only add what the report needs.

Why a completeness flag? Banks PDH has no figures for 2026 Q1, and some early quarters lack a segment. A total for such a quarter would silently leave a segment out. The flag is computed from the data (a quarter is complete when all 4 segments report all 5 headline measures; 55 of 67 quarters are), and the dashboard defaults to the latest complete quarter, which is 2025 Q4.

The model (all relationships many to one, single direction, filter flows from the dimension to the fact):

- dim_date (one) to fact_mortgage_measure (many) on date_key
- dim_segment (one) to fact_mortgage_measure (many) on segment_key
- dim_measure (one) to fact_mortgage_measure (many) on measure_key
- dq_rule (one) to dq_check_result (many) on rule_id
- dq_reconciliation, dq_issue_log and expected_kpi stand alone. They are lookup tables for the data quality page and the test page, not part of the star.

dim_date[prior_quarter_key] is deliberately not a relationship. It is only looked up by DAX (LOOKUPVALUE).

## 3. The most important idea: positions, not flows

Every value here is a position at a quarter end (a balance, a count of accounts). A position can be added across segments in one quarter. It must never be added across quarters: adding 4 quarter-end balances gives a number that means nothing. Power BI would happily do it, because SUM adds whatever is in the filter context.

So every base measure picks exactly one quarter, called the report date:

- If one quarter is in scope (a slicer pick, or one point on a chart axis), that is the report date.
- Otherwise it falls back to the latest complete quarter.

Each base measure then runs CALCULATE with REMOVEFILTERS on dim_date and a filter on that single date. The date is read into a variable first, outside CALCULATE, so a chart axis still shows a different value at each point and the line is not flattened.

## 4. The measures, in plain words

Report date group: Latest Complete Quarter Date, Report Date, Reporting Quarter Label, Prior Quarter Date, Is Complete Quarter.

Base measures: Arrears Accounts, Outstanding Accounts, Arrears Balance, Outstanding Balance, Arrears Amount. Each filters dim_measure[measure_code], so only the published total row is used and a total is never added to its own components.

Rates: Arrears Rate (Accounts) is accounts in arrears divided by all accounts. Arrears Rate (Balance) is the balance of accounts in arrears divided by total balance. DIVIDE returns blank instead of an error when the denominator is zero or missing.

Display units: the source is in thousands of euro. Outstanding Balance (EUR bn) divides by 1,000,000. Arrears Amount (EUR m) divides by 1,000.

Quarter on quarter: the data is quarterly, so the comparison is quarter on quarter, never month on month. The prior quarter comes from prior_quarter_key in dim_date. The change measures return blank when either quarter is missing, so a gap is never shown as a change from zero.

Arrears buckets: the source changed its bucket scheme in 2012 and 2019, so the pipeline maps every scheme to three buckets (Up to 90 days, 91 to 180 days, Over 180 days). Put dim_measure[harmonised_bucket] on a chart axis and use Accounts in Arrears by Bucket.

Risk ranking: Segment Risk Rank (RANKX over the segments in view, 1 is the highest arrears rate) and Highest Risk Segment (the name, for a card).

Honesty guards: Segments Reporting, Completeness Note (a text line such as "2025 Q4: 4 of 4 segments reported.") and Arrears Rate Market Trend (blank unless all 4 segments report, so the market line never mixes a full market with a partial one).

Data quality: DQ Rules Run, Passed, Warning, Info, Failed, DQ Pass Rate, Reconciliation Steps, Reconciliation Matched, Issues Logged, Issue Rows Affected. These read the dq tables built on Day 2.

## 5. Step by step in Power BI Desktop

Open Power BI Desktop. Do not worry about the look yet. Day 4 does the pages.

1. Home, Get data, Text/CSV. Go to the powerbi/data folder in your repository. Pick dim_date.csv, then Load. Repeat for dim_segment, dim_measure, fact_mortgage_measure, dq_rule, dq_check_result, dq_reconciliation, dq_issue_log and expected_kpi (9 files in total). Keep the table names equal to the file names, because the DAX uses them.
2. Open Table view (the grid icon on the left). For each table check the data types, and fix any that are wrong with Column tools, Data type. dim_date: quarter_end_date is Date, is_complete_quarter and is_latest_complete_quarter are True/False. dim_measure: is_total is True/False. fact_mortgage_measure: value is Whole number. expected_kpi: kpi_value is Decimal number. If a True/False column came in as Text, change it. The DAX compares to TRUE() and FALSE().
3. Select dim_date, then the quarter_label column, then Column tools, Sort by column, quarter_sort. Without this the labels sort alphabetically, which happens to look right here but is the habit to build.
4. Open Model view (the diagram icon). Check the relationships Power BI guessed. Delete any that are not in section 2. In particular there must be no relationship from dim_date[prior_quarter_key]. Create the missing ones by dragging the key from the dimension onto the fact. Each must be Many to one, with cross filter direction Single. Do not mark dim_date as a date table. That feature wants a continuous daily calendar, this table is quarterly, and no DAX here uses time intelligence functions.
5. Home, Enter data. Make an empty table, name it _Measures, click Load.
6. Select _Measures. For each measure in powerbi/measures.dax: Home, New measure, paste the whole measure (the line with the name through the closing bracket), press Enter. Do them in file order. Measures that refer to others must come after them. Power BI shows a red underline when a referenced measure does not exist yet.
7. Set formats (Measure tools, Format): rates and shares as Percentage with 2 decimals (1 decimal for Over 180 Days Share); the EUR bn measures as Decimal number with 1 decimal; Arrears Amount (EUR m) with 1 decimal; QoQ Change Arrears Rate (pp) with 2 decimals; counts as Whole number with thousands separator.
8. Smoke test on a blank report page. Add a Card with Arrears Accounts. It must show 41,018. Add a Card with Reporting Quarter Label. It must show 2025 Q4. If either is wrong, stop and fix before building anything else.
9. File, Save as, powerbi/mortgage_mi.pbix.

## 6. Answer key for 2025 Q4

These come from dq.expected_kpi (powerbi/data/expected_kpi.csv), computed in SQL. Day 4 compares the dashboard against them. Balances are in thousands of euro as published.

All segments: arrears accounts 41,018; outstanding accounts 745,765; arrears rate (accounts) 5.50 percent; arrears balance 8,049,539; outstanding balance 115,399,397 (115.4 bn euro); arrears rate (balance) 6.98 percent; over 180 days share 56.83 percent; change in arrears accounts against 2025 Q3 minus 1,389; change in arrears rate minus 0.17 points.

Banks BTL: arrears accounts 1,016; outstanding accounts 29,226; arrears rate 3.48 percent; outstanding balance 2,651,021; over 180 days share 47.64 percent; change in arrears accounts minus 263.

Banks PDH: arrears accounts 13,421; outstanding accounts 594,624; arrears rate 2.26 percent; outstanding balance 91,747,981; over 180 days share 28.57 percent; change in arrears accounts minus 32.

Non-Banks BTL: arrears accounts 4,770; outstanding accounts 18,094; arrears rate 26.36 percent; outstanding balance 3,973,397; over 180 days share 80.23 percent; change in arrears accounts minus 252.

Non-Banks PDH: arrears accounts 21,811; outstanding accounts 103,821; arrears rate 21.01 percent; outstanding balance 17,026,998; over 180 days share 69.52 percent; change in arrears accounts minus 842.

Ranking by arrears rate (accounts) in 2025 Q4: 1 Non-Banks BTL, 2 Non-Banks PDH, 3 Banks BTL, 4 Banks PDH.

Every other quarter and segment is in expected_kpi.csv.

## 7. What you can and cannot say about these numbers

- The data is aggregate by lender group and portfolio. It has no loans, customers or PTSB figures, so the project shows how to build mortgage MI, not what PTSB's arrears are.
- The non-bank figures are much higher than the bank figures. This data does not explain why. A plausible reason is that non-bank firms hold books bought from banks, but that is a hypothesis to check, not something this data proves. Do not call non-banks riskier lenders.
- The arrears rate here is accounts in arrears divided by accounts outstanding, as published. It is not a probability of default.
- "Over 180 days" is a harmonised bucket built by this project from the source's changing schemes. The mapping is in dim_measure and documented in docs/02.

## 8. Interview questions this day prepares you for

Why not just SUM the value column? Because the rows are different measures and different quarters. A SUM with no filters adds accounts to euro balances and quarter ends together. Every measure filters to one measure code and one quarter first.

What is a measure compared with a calculated column? A column is computed once per row when the data loads and stored. A measure is computed when a visual asks for it, in the filter context of that visual. Rates must be measures: the rate of a total is not the sum of rates.

What is filter context, and what does CALCULATE do? Filter context is the set of filters on a number at that moment (slicers, rows and columns of the visual, other filters). CALCULATE changes that context for the expression inside it. REMOVEFILTERS clears filters, and a filter argument adds one.

Why read the report date into a variable before CALCULATE? A variable is evaluated once, in the context where it is defined. Reading it outside CALCULATE keeps the chart axis context, so each point shows its own quarter. Reading it inside would see the already changed context.

Why REMOVEFILTERS on dim_date? Otherwise a chart axis filter on the quarter would combine with the filter for the prior quarter and return nothing.

Why import mode, not DirectQuery? The data is small (19,199 fact rows), static and quarterly. Import is faster and works offline. DirectQuery earns its place for large or live data.

Why one fact table with a measure dimension, not a wide table with a column per measure? The source publishes 133 different measures that change over time. A new line item is a new dim_measure row, not a schema change. The cost is that DAX must filter dim_measure, which is what measure_code is for.

How do you know the DAX is right? Three independent routes to the same figures: SQL (dq.expected_kpi), plain Python reading the CSV files, and the DAX on the dashboard. Day 4 records the comparison.

How do you handle missing data? Banks PDH has no figures for 2026 Q1. The dashboard defaults to the last complete quarter, shows blank for the missing segment, states "3 of 4 segments reported" when a quarter is incomplete, and never turns a missing figure into zero.
