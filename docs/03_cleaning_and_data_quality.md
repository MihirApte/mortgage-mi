# Cleaning rules, data quality framework and test evidence

Everything here was run on the real Central Bank of Ireland file. Counts are queried from the database, not estimated.

## Pipeline and outcome

- raw: 19,199 rows, loaded as text and never changed.
- clean: 19,199 rows. 13,194 valid, 6,005 corrected, 0 quarantined.
- mart: 19,199 fact rows, 133 measures, 67 quarters, 2 lender groups, 2 portfolios.
- Value control total: 15,395,850,005 in the fact table, matched by a separate Python script that reads the CSV.

Zero quarantined rows is a real result, not a missing feature. The quarantine rules exist and are proven by a dedicated test (see "Test evidence"), but this particular file never triggers them.

## Cleaning rules (sql/06_clean_build.sql)

1. C1: trim text and cast row and column position to integers.
2. C2: choose the value column from the metric type. Euro metrics (Balance, Arrears) come from Observation. Every other metric is a count and comes from Number of Accounts.
3. C3: strip thousands commas and padding spaces, then cast to bigint. If anything other than digits remains, the value is NULL and the row is quarantined.
4. C4: if the other value column is also filled (70 rows in the 31 March 2026 return), ignore it, keep the expected column and flag the row corrected. The ignored text is kept in clean.stray_value_text.
5. C5: map each reporting date to its calendar quarter end. Dates that are already quarter ends stay. A weekday up to 3 days before quarter end is treated as the last working day. Two malformed dates are repaired using an explicit table, clean.reporting_date_map_repairs, which stores the evidence. Anything else is unmapped and quarantined.
6. C6: if two rows land on the same grain after mapping, keep the lowest raw_row_id and quarantine the rest.

Why was the stray value ignored, and how do I know the kept value is right? For the 70 rows, the Number of Accounts value I kept moves a median of 3.3 percent against the previous quarter (6.3 percent for all other count rows in that return). The stray figures would imply a median move of about 5,152 percent. A count that large is not credible, so the stray figure is the contaminated one. The evidence is computed in the tracker (DQI-04) from the data.

## The 23 data quality rules (dq.rule, sql/08 and sql/09)

Eight dimensions: completeness (3 rules), validity (4), uniqueness (3), reasonableness (3), consistency (3), referential integrity (4), coverage (2) and continuity (1). Each rule has a severity: error stops the pipeline, warning is an explained condition that is logged, info is recorded for transparency.

Result of the run on the real data: 18 pass, 4 warn, 1 info, 0 errors.

The four warnings, all explained in the tracker:
- DQ02, 70 rows with both value columns filled (resolved by rule C4).
- DQ06, 5,935 rows on 21 reporting dates that are not calendar quarter ends (resolved by rule C5).
- DQ16, 2 segment quarters where the four legal status counts do not add up to total accounts in arrears (source inconsistency, accepted).
- DQ21, 5 core measures missing for Banks PDH in 2026 Q1 (not imputed).

The one info item is DQ23, where possessions at the start of a quarter differ from the previous quarter end in 53 of 240 comparisons.

The business-logic rules in detail:
- DQ12: arrears amount never exceeds the balance of the same line item. 5,121 line items tested, 0 failures.
- DQ13: accounts in arrears never exceed accounts outstanding, and the balance in arrears never exceeds total balance. 490 comparisons, 0 failures.
- DQ14: the count of accounts in arrears equals the sum of its buckets. 245 comparisons, all exact.
- DQ15: the same test for euro amounts, with a tolerance. Euro figures are published rounded to thousands, so each can be out by 0.5, and the allowed gap is (number of buckets + 1) / 2. The largest gap observed is 2 thousand euro, and 122 of 490 comparisons differ by rounding, all inside the tolerance.

## Rules I tested and did not adopt

I checked a possession roll-forward (start plus repossessed plus surrendered minus disposed equals end). It held in only 79 of 186 comparisons, so the published categories clearly do not capture every movement. I did not turn it into a rule, because a rule that the source itself breaks would only produce noise. This is why a rule is explored before it is written.

## Reconciliation (dq.reconciliation)

102 steps, all matching. 85 are internal: raw to clean, clean status totals, clean to fact, lineage, value control total, and row counts by category, by lender and portfolio segment, and by quarter (67 quarters, from the raw file through the date map to the fact table). 17 are external, compared with the Python script: total rows, total value, stray rows, euro and count rows, rows by category and by segment.

## Test evidence (a check that never fails proves nothing)

- sql/11_dq_selftest.sql corrupts the data in 21 specific ways inside a transaction and requires every targeted rule to report more failures than the baseline. All 21 detect their corruption. Three database constraints (primary key, foreign key and the non-negative check) are also shown to reject bad rows. The transaction is rolled back and the data is confirmed unchanged.
- sql/13_clean_quarantine_test.sql corrupts six raw rows, rebuilds the clean layer, and requires each to be quarantined for the right reason: non-numeric value, unknown lender group, unknown portfolio, unmappable date, non-numeric position, duplicate grain. All six pass, then it rolls back.
- Every script is repeatable. The whole pipeline was run from an empty database and then rerun twice on top of itself with identical results.

## Issue tracker

docs/dq_issue_tracker.csv is exported from dq.issue_log. It has 11 issues. Each has the rule that detects it, the number of rows affected, a severity, the resolution and a status (resolved, accepted or monitor). Accepted means a known limitation was left in place on purpose and is stated openly.

## Interview questions you should be able to answer

Why quarantine rows instead of deleting them?
Deleting makes row counts impossible to reconcile and hides problems. A quarantined row stays visible with a reason, and the reconciliation proves nothing disappears silently.

Why a tolerance on the euro totals but not on the counts?
Counts are whole numbers and must match exactly. Euro amounts are published rounded to thousands, so a total and the sum of its parts can legitimately differ by rounding. The tolerance is derived from the rounding, not picked to make the test pass.

You say 01/12/2025 is Q4 2025. How sure are you?
It is an inference. That date holds a full return, no other date exists for Q4 2025, and its size matches adjacent quarters. It is logged as accepted and should be confirmed with the publisher before anyone relies on it.

What happens when the check finds a real error in production?
Error rules stop the run before the mart is trusted. Warnings continue, because they are known and explained, and appear in the tracker and on the dashboard's data quality page.

How do you know your checks work?
I corrupted the data on purpose, in 21 ways, and required each rule to catch its corruption. Then I rolled back and proved the data was unchanged.

Why a second tool for the control totals?
A pipeline checking itself can repeat its own mistake. A short Python script with no shared code reads the CSV and arrives at the same total, 15,395,850,005, so a logic error would have to be made twice in two different languages.

Why not impute the missing Banks PDH figures for Q1 2026?
Any imputed number would be mine, not the Central Bank's, and it would appear on a regulatory-style dashboard as if it were real. Blank values with a documented reason are more honest and more defensible.
