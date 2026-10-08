# Data dictionary

Every table and column in the pipeline, and every Power BI measure. The column lists below were generated from the live PostgreSQL catalogue (information_schema) of the final database. At generation time every one of the 167 columns in the 23 tables was checked to have a description, and none was left out. If you add or change a column, update this file.

## How to read it

- Layers run in one direction: raw, then clean, then mart, then the reporting views read by Power BI. The dq schema holds the rules, the results and the tests.
- Data types are PostgreSQL types. Raw columns are all text on purpose.
- Units: euro measures are in thousands of euro as published (a value of 115,399,397 means 115.4 billion euro). Count measures are numbers of accounts. Repossession measures are numbers of properties.
- Values are positions at a quarter end (balances, counts). They can be added across segments in one quarter but never across quarters.
- Keys: the fact table joins to dim_date on date_key, to dim_lender_group on lender_group_key, to dim_portfolio on portfolio_key, and to dim_measure on measure_key. The Power BI views replace the two segment keys with one segment_key.

## Glossary

- PDH: principal dwelling house, a mortgage on the borrower's home.
- BTL: buy to let, a mortgage on a property bought to rent out.
- Account in arrears: a mortgage account that is behind on payments.
- Arrears amount: the overdue amount itself. Arrears balance: the whole outstanding balance of the accounts that are in arrears. They are different numbers.
- Arrears rate (accounts): accounts in arrears divided by total accounts outstanding. Arrears rate (balance): balance of accounts in arrears divided by total outstanding balance.
- Banks and Non-Banks: the two lender groups in the Central Bank of Ireland return.
- Harmonised bucket: the project's own mapping of the source's changing arrears age schemes to three buckets that stay comparable over time.
- Quarantined row: a row the clean layer cannot use. Quarantined rows stay in clean with a reason and never reach the mart. There are none in the current data.
- Source: Central Bank of Ireland, Residential Mortgage Arrears and Repossession Statistics, licence CC BY 4.0. See data/SOURCE.md.

## Tables and columns

### clean.mortgage_observation

Layer clean. One row per raw row, typed and flagged. Never drops a row: a row that cannot be used is marked quarantined with a reason.

- raw_row_id (bigint): Primary key. Points to raw.cbi_mortgage_arrears_open_data.raw_row_id.
- quarter_end_date (date): Calendar quarter end the row belongs to. Null if the date could not be mapped (row is then quarantined).
- date_rule (text): How the quarter end was derived: as_published, working_day_adjusted or repaired_malformed_date.
- lender_group (text): Trimmed lender group.
- portfolio_code (text): Trimmed portfolio code, PDH or BTL.
- category (text): Trimmed category.
- row_position (smallint): Row position cast to a number.
- column_position (smallint): Column position cast to a number.
- row_label (text): Trimmed row label.
- observation_type (text): Trimmed observation type.
- value_column (text): Which raw column holds the real value for this row: observation (euro metrics) or number_of_accounts (counts).
- value (bigint): The measure value as a whole number, after removing commas and spaces. Null if the row is quarantined.
- number_text_cleaned (boolean): TRUE if commas or spaces had to be removed to read the number.
- stray_value_ignored (boolean): TRUE if the other value column also held a figure, which was ignored (70 rows in the 31 March 2026 return).
- date_remapped (boolean): TRUE if the published date differs from the calendar quarter end.
- stray_value_text (text): The ignored stray figure, kept as text for audit.
- dq_status (text): valid, corrected or quarantined.
- dq_reason (text): Why a row is corrected or quarantined. Empty for valid rows.

### clean.reporting_date_map

Layer clean. Maps each distinct published reporting date that is a normal date to its calendar quarter end, with the rule used.

- reporting_date_raw (text): Published date text.
- quarter_end_date (date): Calendar quarter end it maps to.
- date_rule (text): Rule used for the mapping.

### clean.reporting_date_map_repairs

Layer clean. The two malformed reporting dates in the source, each with the written evidence for the repair. These are inferences, not facts confirmed by the publisher.

- reporting_date_raw (text): Malformed published date text.
- quarter_end_date (date): Quarter end it was repaired to.
- evidence (text): Written evidence for the repair, including that it is an inference.

### dq.check_result

Data quality. The result of each rule on the last pipeline run: rows tested, rows failed and status.

- check_id (bigint): Row number.
- run_label (text): Label of the run.
- rule_id (text): Foreign key to dq.rule.
- rows_tested (bigint): How many rows or items the rule examined.
- rows_failed (bigint): How many failed.
- pct_failed (numeric): Failed as a percentage of tested.
- status (text): pass, fail, warn or info.
- detail (text): Plain language note about the result.
- checked_at (timestamp with time zone): Timestamp of the check.

### dq.expected_kpi

Testing. The headline KPIs computed in plain SQL for every quarter and segment. The answer key for the Power BI tests.

- quarter_label (text): Quarter label.
- segment (text): Segment label, or All segments (only for quarters where all 4 report).
- kpi_code (text): KPI name, for example arrears_rate_accounts.
- kpi_value (numeric): Value computed in SQL. Null where it cannot be computed.

### dq.issue_log

Data quality. The tracker of problems found in the source and what was done about each (11 issues).

- issue_id (text): DQI-01 to DQI-11.
- found_in (text): Where the problem was found.
- rule_ref (text): Related data quality rule.
- issue (text): The problem in plain words.
- rows_affected (bigint): Rows touched, computed from the data. One row can be affected by several issues, so do not add this column.
- severity (text): warning or info.
- resolution (text): What was done.
- status (text): resolved, accepted or monitor.

### dq.reconciliation

Data quality. Row count and total comparisons between layers and against independent controls (102 steps).

- recon_id (bigint): Row number.
- check_name (text): Group of the comparison, for example Row count or Independent control (Python).
- breakdown (text): The slice compared, for example one category or segment.
- from_layer (text): Source side of the comparison.
- from_value (numeric): Value on the source side.
- to_layer (text): Target side of the comparison.
- to_value (numeric): Value on the target side.
- difference (numeric): Target minus source.
- status (text): match or mismatch. Any mismatch stops the pipeline.
- note (text): Explanation where one is needed.

### dq.rule

Data quality. The 23 rules: what is tested, at which layer, how severe a failure is and what happens on failure.

- rule_id (text): Primary key, DQ01 to DQ23.
- dimension (text): Quality dimension: completeness, validity, uniqueness, reasonableness, consistency, referential integrity, coverage or continuity.
- layer (text): Layer the rule tests: raw, clean or mart.
- rule_name (text): Short name.
- description (text): What is tested.
- severity (text): error, warning or info.
- on_failure (text): What happens when the rule fails.

### dq.v_arrears_amount_vs_balance

Data quality view. Compares the arrears amount with the outstanding balance of the same arrears bucket.

- date_key (integer): Quarter end key, yyyymmdd. Joins to mart.dim_date.
- lender_group_key (smallint): Joins to mart.dim_lender_group.
- portfolio_key (smallint): Joins to mart.dim_portfolio.
- category (text): Source category.
- row_position (smallint): Row position in the source.
- balance_value (bigint): Outstanding balance of the bucket.
- arrears_value (bigint): Arrears amount of the bucket.

### dq.v_arrears_total_vs_buckets

Data quality view. Compares the published total in arrears with the sum of its age buckets, by metric.

- date_key (integer): Quarter end key, yyyymmdd. Joins to mart.dim_date.
- lender_group_key (smallint): Joins to mart.dim_lender_group.
- portfolio_key (smallint): Joins to mart.dim_portfolio.
- metric_column (smallint): Metric compared: accounts, balance or arrears amount.
- total_value (bigint): Published total.
- leaf_sum (numeric): Sum of the age buckets.
- n_leaf (bigint): Number of buckets summed.
- difference (numeric): Total minus sum.

### dq.v_arrears_vs_outstanding

Data quality view. Compares the arrears total with the total outstanding.

- date_key (integer): Quarter end key, yyyymmdd. Joins to mart.dim_date.
- lender_group_key (smallint): Joins to mart.dim_lender_group.
- portfolio_key (smallint): Joins to mart.dim_portfolio.
- metric_column (smallint): Metric compared: accounts, balance or arrears amount.
- arrears_total (bigint): Total in arrears.
- outstanding_total (bigint): Total outstanding.

### dq.v_core_measure_coverage

Data quality view. Which core measures are present for each segment and quarter.

- date_key (integer): Quarter end key, yyyymmdd. Joins to mart.dim_date.
- lender_group_key (smallint): Joins to mart.dim_lender_group.
- portfolio_key (smallint): Joins to mart.dim_portfolio.
- measure_key (integer): Joins to mart.dim_measure.
- category (text): Source category.
- source_row_position (smallint): Source row position.
- source_column_position (smallint): Source column position.
- is_present (boolean): TRUE if a value exists.

### dq.v_legal_status_vs_arrears_total

Data quality view. Compares the sum of legal status counts with the total accounts in arrears.

- date_key (integer): Quarter end key, yyyymmdd. Joins to mart.dim_date.
- lender_group_key (smallint): Joins to mart.dim_lender_group.
- portfolio_key (smallint): Joins to mart.dim_portfolio.
- legal_sum (numeric): Sum of the legal status counts.
- arrears_total (bigint): Total in arrears.
- difference (numeric): Total minus sum.

### dq.v_possession_continuity

Data quality view. Compares possessions at the start of a quarter with the end of the prior quarter.

- date_key (integer): Quarter end key, yyyymmdd. Joins to mart.dim_date.
- lender_group_key (smallint): Joins to mart.dim_lender_group.
- portfolio_key (smallint): Joins to mart.dim_portfolio.
- start_of_quarter (bigint): Possessions at the start of the quarter.
- prior_quarter_end (bigint): Possessions at the end of the prior quarter.

### mart.dim_date

Layer mart. Dimension. One row per calendar quarter end from 2009 Q3 to 2026 Q1 (67 rows), generated from calendar rules.

- date_key (integer): Primary key. The quarter end as yyyymmdd, for example 20251231.
- quarter_end_date (date): The quarter end date.
- calendar_year (smallint): Calendar year.
- calendar_quarter (smallint): Quarter number 1 to 4.
- quarter_label (text): Display label such as 2025 Q4.
- quarter_sort (integer): Year times 10 plus quarter. Sorts the label correctly.
- prior_quarter_key (integer): date_key of the previous quarter. Null for the first quarter. Used for quarter on quarter change.

### mart.dim_lender_group

Layer mart. Dimension. The two lender groups in the source: Banks and Non-Banks.

- lender_group_key (smallint): Primary key.
- lender_group_name (text): Banks or Non-Banks.
- description (text): Plain language description of the group.

### mart.dim_measure

Layer mart. Dimension. What is measured: one row per category, row position and column position in the source (133 rows).

- measure_key (integer): Primary key.
- category (text): Source category, for example Arrears.
- source_row_position (smallint): Row position in the source.
- source_column_position (smallint): Column position in the source.
- line_item (text): Tidied label of the line.
- source_row_label (text): Label exactly as published.
- metric_name (text): Accounts, Outstanding balance, Arrears amount, Properties and so on.
- unit (text): accounts, properties or EUR thousands.
- is_total (boolean): TRUE for the published total in arrears. A total equals the sum of its components, so never add a total and its components.
- harmonised_bucket (text): Arrears age bucket comparable across all years: Up to 90 days, 91 to 180 days or Over 180 days. Null outside the arrears detail rows.
- harmonised_bucket_sort (smallint): Sort order of the bucket, 1 to 3.
- measure_code (text): Stable code for the 5 headline measures, used by DAX. Null for all other measures.

### mart.dim_portfolio

Layer mart. Dimension. The two portfolios in the source: principal dwelling house and buy to let.

- portfolio_key (smallint): Primary key.
- portfolio_code (text): PDH or BTL.
- portfolio_name (text): Full name of the portfolio.

### mart.fact_mortgage_measure

Layer mart. Fact. Grain: one value per quarter, lender group, portfolio and measure (19,199 rows). The primary key on those four keys enforces the grain.

- date_key (integer): Foreign key to dim_date.
- lender_group_key (smallint): Foreign key to dim_lender_group.
- portfolio_key (smallint): Foreign key to dim_portfolio.
- measure_key (integer): Foreign key to dim_measure.
- value (bigint): The measure value. Whole number, never negative. Unit comes from dim_measure.
- source_raw_row_id (bigint): Lineage pointer to raw.cbi_mortgage_arrears_open_data.raw_row_id.

### mart.v_bi_dim_date

Reporting view over mart.dim_date for Power BI. Adds two completeness flags computed from the data.

- date_key (integer): Quarter end key, yyyymmdd. Joins to mart.dim_date.
- quarter_end_date (date): The quarter end date.
- calendar_year (smallint): Calendar year.
- calendar_quarter (smallint): Quarter number 1 to 4.
- quarter_label (text): Display label such as 2025 Q4.
- quarter_sort (integer): Sort key for the label.
- prior_quarter_key (integer): date_key of the previous quarter.
- is_complete_quarter (boolean): TRUE when all 4 segments report all 5 headline measures (55 of 67 quarters).
- is_latest_complete_quarter (boolean): TRUE for the newest complete quarter. The dashboard defaults to it (2025 Q4).

### mart.v_bi_dim_segment

Reporting view for Power BI. The 4 combinations of lender group and portfolio, with one key.

- segment_key (integer): Lender group key times 10 plus portfolio key.
- lender_group_key (smallint): Key of the lender group.
- portfolio_key (smallint): Key of the portfolio.
- lender_group_name (text): Banks or Non-Banks.
- portfolio_code (text): PDH or BTL.
- portfolio_name (text): Full portfolio name.
- segment_label (text): Display label such as Non-Banks BTL.

### mart.v_bi_fact

Reporting view for Power BI. The same rows and values as mart.fact_mortgage_measure, with one segment key in place of the two keys.

- date_key (integer): Quarter end key, yyyymmdd. Joins to mart.dim_date.
- segment_key (integer): Segment key as in v_bi_dim_segment.
- measure_key (integer): Joins to mart.dim_measure.
- value (bigint): The measure value.
- source_raw_row_id (bigint): Lineage pointer to raw_row_id.

### raw.cbi_mortgage_arrears_open_data

Layer raw. The source file loaded as text, untouched. One row per source row (19,199 rows). Nothing is cleaned, typed or removed here, so any later layer can be traced back to exactly what the publisher sent.

- raw_row_id (bigint): Surrogate row number in file order, starting at 1. The lineage anchor: every later layer points back to it.
- source_file (text): Name of the file the row came from.
- loaded_at (timestamp with time zone): Timestamp of the load.
- reporting_date (text): Reporting date as published, text in dd/mm/yyyy. Usually the last working day of the quarter. Two values are malformed.
- entity_group (text): Lender group as published: Banks or Non-Banks.
- format_code (text): Portfolio as published: PDH (principal dwelling house) or BTL (buy to let).
- category (text): Table of the return the row belongs to, for example Arrears or Total Outstanding. 8 values.
- row_position (text): Line number within the category, as published.
- column_position (text): Column number within the category, as published.
- row_label (text): Text label of the line, as published.
- observation_type (text): What the value is, as published, for example a euro amount in thousands or a number of accounts.
- observation (text): Value for euro measures, as text. May contain thousands commas and spaces.
- number_of_accounts (text): Value for count measures, as text. Euro rows leave it empty.

## Power BI measures (powerbi/measures.dax)

Each measure is defined with comments in powerbi/measures.dax. In short:

- Latest Complete Quarter Date: The newest quarter where all 4 segments report all 5 headline measures (flag computed in SQL).
- Report Date: If one quarter is in scope (slicer pick, or one point on a chart axis) use it. Otherwise fall back to the latest complete quarter, so a card never adds quarters together.
- Reporting Quarter Label: See powerbi/measures.dax.
- Prior Quarter Date: Uses prior_quarter_key from dim_date, so the first quarter in the data correctly has no prior.
- Is Complete Quarter: See powerbi/measures.dax.
- Arrears Accounts: Number of mortgage accounts in arrears (total row only, so buckets are not added to their total).
- Outstanding Accounts: See powerbi/measures.dax.
- Arrears Balance: Outstanding balance of the accounts that are in arrears, in EUR thousands as published.
- Outstanding Balance: Total outstanding balance of all mortgage accounts, in EUR thousands as published.
- Arrears Amount: The overdue amount itself (what is owed and unpaid), in EUR thousands as published.
- Arrears Rate (Accounts): Accounts in arrears divided by all accounts. Format as percentage, 2 decimals.
- Arrears Rate (Balance): Balance of accounts in arrears divided by total balance. Format as percentage, 2 decimals.
- Outstanding Balance (EUR bn): Source is in EUR thousands, so one million thousands is one billion euro. Format 0.0.
- Arrears Balance (EUR bn): See powerbi/measures.dax.
- Arrears Amount (EUR m): EUR thousands divided by 1000 gives EUR millions. Format #,0.0.
- Arrears Accounts PQ: See powerbi/measures.dax.
- Outstanding Accounts PQ: See powerbi/measures.dax.
- Outstanding Balance PQ: See powerbi/measures.dax.
- Arrears Rate (Accounts) PQ: See powerbi/measures.dax.
- Segments Reporting: How many of the 4 segments have an arrears figure in the report quarter.
- Segments Reporting PQ: How many of the 4 segments have an arrears figure in the prior quarter.
- Like For Like: TRUE when a change against the prior quarter compares the same segments: either one segment is in view, or the same number of segments reported in both quarters (the data shows that an equal count always means the same segments). FALSE would mean comparing a partial market with a full one, which is not a real movement, so the change measures return blank.
- QoQ Change Arrears Accounts: BLANK when either quarter is missing, or when the two quarters do not cover the same segments, so a missing quarter is never shown as a change from zero and a partial market is never compared with a full one.
- QoQ Change Arrears Rate (pp): Change in the arrears rate in percentage points. Format 0.00. Example: -0.17 means 0.17 points lower.
- QoQ Change Outstanding Balance: See powerbi/measures.dax.
- Accounts in Arrears by Bucket: Put dim_measure[harmonised_bucket] on the visual axis. Leaf rows only (is_total FALSE), so nothing is counted twice. SQL proves the 3 buckets add exactly to the total in every segment and quarter.
- Over 180 Days Accounts: See powerbi/measures.dax.
- Over 180 Days Share: Share of arrears accounts that are more than 180 days behind. Format percentage, 1 decimal.
- Segment Risk Rank: 1 is the segment with the highest arrears rate among the segments in view. Blank on a total row, because a total is not a segment and has no rank.
- Highest Risk Segment: Name of the segment with the highest arrears rate. Use on a card.
- Share of Total Outstanding Balance: How much of the whole market balance sits in the segment in view. Format percentage.
- Completeness Note: Put this on a card as a subtitle under the KPIs. It states plainly when a segment is missing.
- Arrears Rate Market Trend: For the market wide trend line. Shows a value only where all 4 segments report, so the line never mixes a full market with a partial one.
- DQ Rules Run: See powerbi/measures.dax.
- DQ Rules Passed: See powerbi/measures.dax.
- DQ Rules Warning: See powerbi/measures.dax.
- DQ Rules Info: See powerbi/measures.dax.
- DQ Rules Failed: Error level failures. The pipeline gate stops the build when this is above zero, so on a built dashboard it is zero. It is shown anyway, because a quality page that hides its failures is not honest.
- DQ Pass Rate: See powerbi/measures.dax.
- Reconciliation Steps: See powerbi/measures.dax.
- Reconciliation Matched: See powerbi/measures.dax.
- Issues Logged: See powerbi/measures.dax.
- Issue Rows Affected: See powerbi/measures.dax.
