# Star schema design and interview notes

## Layers

1. raw: the file as received. All text, never changed.
2. clean: one row per raw row, typed and standardised, with a data quality flag. Built on Day 2.
3. mart: the star schema below. Built on Day 2, read by Power BI on Day 3.
4. dq: rule results, reconciliation counts and the issue tracker. Built on Day 2.

## Grain

One row in mart.fact_mortgage_measure is one reported number for one quarter, one lender group, one portfolio and one measure. The primary key (date_key, lender_group_key, portfolio_key, measure_key) enforces that grain, so duplicates cannot enter the mart.

## Tables

- fact_mortgage_measure: date_key, lender_group_key, portfolio_key, measure_key, value, source_raw_row_id.
- dim_date: one row per calendar quarter end, 2009 Q3 to 2026 Q1 (67 rows), with a quarter label, a sort key and a link to the prior quarter for quarter-on-quarter measures.
- dim_lender_group: Banks, Non-Banks.
- dim_portfolio: PDH (principal dwelling house), BTL (buy-to-let).
- dim_measure: 133 rows describing what is measured: category, cleaned line item, metric, unit, whether the row is a total, and a harmonised arrears bucket.

## Questions you should be able to answer

Why a star schema and not just the clean table?
Power BI, and most BI tools, are built for a star shape. Filters flow from small descriptive tables (dimensions) to one large table of numbers (the fact). Dimensions are reused by every visual, so a slicer on lender group filters everything consistently, and measures stay simple.

What is the grain and why does it matter?
Grain is what one fact row means. Stating it first prevents mixed levels in one table, which is the usual source of double counting. Here it is quarter by lender group by portfolio by measure.

Why one long fact table instead of a column per metric?
The Central Bank publishes 133 line item and metric combinations and changed the arrears buckets twice. A wide table would need a new column whenever the return changes. With a long fact and dim_measure, a new line item is a new dimension row. The trade-off is that DAX measures filter dim_measure by category, line item and metric, which I show on Day 3.

Why are all raw columns text?
A typed load rejects or silently converts bad values. In this file numbers carry commas and spaces, and two cells conflict. Keeping raw as text means nothing is lost, and every fix is a visible, testable step in the clean layer.

Why does the load declare Windows-1252?
The euro sign in the file is a single byte, 0x80, which is not valid UTF-8. Declaring the true encoding converts it correctly while the file on disk stays untouched. I proved it: the euro sign appears in 10,832 rows and there are zero replacement characters.

Why surrogate integer keys?
They are small and fast to join, they do not change if the Central Bank edits a label, and they let several source labels map to one dimension row. The natural key (category, row position, column position) is kept as a unique constraint so the mapping stays auditable.

Why is dim_date generated rather than taken from the file?
The file's reporting dates are working-day adjusted (30/12/2016, 28/03/2024) and two are malformed. A generated calendar of true quarter ends gives every date one stable key, and the clean layer maps each source date to it. It also exposes quarters with no data.

What is source_raw_row_id?
A lineage column. Every fact row points to the raw row it came from, so any dashboard number can be traced back to a line in the original CSV.

Why check constraints and foreign keys, given that I also run data quality checks?
Constraints are the last line of defence and stop bad data from ever being stored. Quality checks (Day 2) explain what was found upstream and what was done about it. They do different jobs.

Why PostgreSQL?
It is free, standards-based SQL, and Power BI connects to it natively. The skills (window functions, CTEs, constraints, schemas) transfer directly to SQL Server or Azure SQL, which banks commonly use. The main syntax differences are noted in the README.

Why quarter-on-quarter and not month-on-month?
The Central Bank publishes this return quarterly. A month-on-month figure would need invented monthly data.

## What this design deliberately does not do

- It does not model individual loans or borrowers, because the source has none.
- It does not impute missing Banks PDH figures for 31 March 2026. Gaps are shown and logged.
- It does not add totals and components together. is_total marks rows that must not be summed with their parts.


## Day 3 addition

dim_measure has a measure_code column, filled only for the 5 headline measures, so DAX filters on stable codes. Power BI reads three reporting views (v_bi_dim_segment, v_bi_fact, v_bi_dim_date) built on top of the mart. The mart tables are unchanged. See docs/04_power_bi_model_and_dax.md.
