/*
  10_dq_run.sql
  Purpose : Run the checks on the real data, reconcile layer to layer, build the issue tracker
            and stop the pipeline if any error-level rule fails or any reconciliation breaks.

  Every number in the tracker text is computed from the data at run time, not typed in.
*/

TRUNCATE TABLE dq.check_result, dq.reconciliation, dq.issue_log RESTART IDENTITY;

CALL dq.run_checks('pipeline_run');

/* Helper for reconciliation rows. A match means the two values are equal. */
DROP ROUTINE IF EXISTS dq.log_recon(TEXT, TEXT, TEXT, NUMERIC, TEXT, NUMERIC, TEXT);

CREATE OR REPLACE FUNCTION dq.log_recon(p_name TEXT, p_breakdown TEXT, p_from_layer TEXT, p_from NUMERIC,
                                        p_to_layer TEXT, p_to NUMERIC, p_note TEXT DEFAULT NULL)
RETURNS VOID
LANGUAGE sql
AS $$
    INSERT INTO dq.reconciliation (check_name, breakdown, from_layer, from_value, to_layer, to_value, difference, status, note)
    VALUES (p_name, p_breakdown, p_from_layer, p_from, p_to_layer, p_to, p_from - p_to,
            CASE WHEN p_from = p_to THEN 'match' ELSE 'mismatch' END, p_note);
$$;

/* 1. Row counts, layer to layer */
DO $$ BEGIN PERFORM dq.log_recon('Row count', 'all rows', 'raw', (SELECT count(*) FROM raw.cbi_mortgage_arrears_open_data),
                    'clean', (SELECT count(*) FROM clean.mortgage_observation),
                    'Nothing is deleted between raw and clean'); END $$;

DO $$ BEGIN PERFORM dq.log_recon('Row count', 'clean rows by status', 'clean', (SELECT count(*) FROM clean.mortgage_observation),
                    'clean (valid + corrected + quarantined)',
                    (SELECT count(*) FILTER (WHERE dq_status = 'valid') + count(*) FILTER (WHERE dq_status = 'corrected')
                          + count(*) FILTER (WHERE dq_status = 'quarantined') FROM clean.mortgage_observation),
                    'Every clean row has exactly one status'); END $$;

DO $$ BEGIN PERFORM dq.log_recon('Row count', 'loadable rows', 'clean (valid + corrected)',
                    (SELECT count(*) FROM clean.mortgage_observation WHERE dq_status IN ('valid', 'corrected')),
                    'mart fact', (SELECT count(*) FROM mart.fact_mortgage_measure),
                    'Quarantined rows are the only rows allowed to be missing from the fact table'); END $$;

DO $$ BEGIN PERFORM dq.log_recon('Quarantine isolation', 'quarantined rows present in fact', 'expected', 0,
                    'mart fact',
                    (SELECT count(*) FROM mart.fact_mortgage_measure f
                      WHERE EXISTS (SELECT 1 FROM clean.mortgage_observation c WHERE c.raw_row_id = f.source_raw_row_id AND c.dq_status = 'quarantined')),
                    'Quarantined rows must never reach the mart. Quarantined in clean: '
                    || (SELECT count(*) FROM clean.mortgage_observation WHERE dq_status = 'quarantined')); END $$;

/* 2. Lineage: every loadable raw row appears in the fact exactly once */
DO $$ BEGIN PERFORM dq.log_recon('Lineage', 'distinct raw row ids', 'clean (valid + corrected)',
                    (SELECT count(DISTINCT raw_row_id) FROM clean.mortgage_observation WHERE dq_status IN ('valid', 'corrected')),
                    'mart fact', (SELECT count(DISTINCT source_raw_row_id) FROM mart.fact_mortgage_measure)); END $$;

/* 3. Control total of values */
DO $$ BEGIN PERFORM dq.log_recon('Value total', 'sum of all values', 'clean (valid + corrected)',
                    (SELECT COALESCE(sum(value), 0) FROM clean.mortgage_observation WHERE dq_status IN ('valid', 'corrected')),
                    'mart fact', (SELECT COALESCE(sum(value), 0) FROM mart.fact_mortgage_measure),
                    'Mixes counts and euro thousands, so it is a control total and not a business figure'); END $$;

/* 4. Row counts by category */
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN
        SELECT c.category AS k, c.n AS a, COALESCE(f.n, 0) AS b
        FROM (SELECT category, count(*) AS n FROM clean.mortgage_observation WHERE dq_status IN ('valid', 'corrected') GROUP BY category) AS c
        LEFT JOIN (SELECT dm.category, count(*) AS n FROM mart.fact_mortgage_measure AS fm
                   JOIN mart.dim_measure AS dm USING (measure_key) GROUP BY dm.category) AS f USING (category)
        ORDER BY c.category
    LOOP
        PERFORM dq.log_recon('Row count by category', rec.k, 'clean (valid + corrected)', rec.a, 'mart fact', rec.b);
    END LOOP;
END $$;

/* 5. Row counts by lender group and portfolio */
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN
        SELECT c.lender_group || ' ' || c.portfolio_code AS k, c.n AS a, COALESCE(f.n, 0) AS b
        FROM (SELECT lender_group, portfolio_code, count(*) AS n FROM clean.mortgage_observation WHERE dq_status IN ('valid', 'corrected')
              GROUP BY lender_group, portfolio_code) AS c
        LEFT JOIN (SELECT lg.lender_group_name AS lender_group, p.portfolio_code, count(*) AS n
                   FROM mart.fact_mortgage_measure AS fm
                   JOIN mart.dim_lender_group AS lg USING (lender_group_key)
                   JOIN mart.dim_portfolio AS p USING (portfolio_key)
                   GROUP BY lg.lender_group_name, p.portfolio_code) AS f USING (lender_group, portfolio_code)
        ORDER BY c.lender_group, c.portfolio_code
    LOOP
        PERFORM dq.log_recon('Row count by segment', rec.k, 'clean (valid + corrected)', rec.a, 'mart fact', rec.b);
    END LOOP;
END $$;

/* 6. Row counts by quarter, from the raw file through the date map to the fact table */
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN
        SELECT to_char(q.quarter_end_date, 'YYYY-MM-DD') AS k, q.n AS a, COALESCE(f.n, 0) AS b
        FROM (SELECT m.quarter_end_date, count(*) AS n
              FROM raw.cbi_mortgage_arrears_open_data AS r
              JOIN clean.reporting_date_map AS m ON m.reporting_date_raw = r.reporting_date
              GROUP BY m.quarter_end_date) AS q
        LEFT JOIN (SELECT d.quarter_end_date, count(*) AS n
                   FROM mart.fact_mortgage_measure AS fm JOIN mart.dim_date AS d USING (date_key)
                   GROUP BY d.quarter_end_date) AS f USING (quarter_end_date)
        ORDER BY q.quarter_end_date
    LOOP
        PERFORM dq.log_recon('Row count by quarter', rec.k, 'raw (via date map)', rec.a, 'mart fact', rec.b);
    END LOOP;
END $$;

/* Tracker. Counts and examples are queried, never typed. */
INSERT INTO dq.issue_log (issue_id, found_in, rule_ref, issue, rows_affected, severity, resolution, status)
SELECT 'DQI-01', 'load', 'Day 1 CHECK 4',
       'Source file is encoded as Windows-1252, not UTF-8 (the euro sign is the single byte 0x80)',
       (SELECT count(*) FROM raw.cbi_mortgage_arrears_open_data WHERE observation_type LIKE '%' || chr(8364) || '%'),
       'warning',
       'The load step declares the true encoding. The file on disk is untouched. Verified: zero replacement characters in the raw table.',
       'resolved';

INSERT INTO dq.issue_log (issue_id, found_in, rule_ref, issue, rows_affected, severity, resolution, status)
SELECT 'DQI-02', 'raw', 'DQ04',
       'Numbers are stored as text with thousands commas and leading or trailing spaces',
       (SELECT count(*) FROM clean.mortgage_observation WHERE number_text_cleaned),
       'warning',
       'Clean rule C3 strips commas and spaces and casts to bigint. DQ04 confirms no other text pattern exists, so no value was lost or guessed.',
       'resolved';

INSERT INTO dq.issue_log (issue_id, found_in, rule_ref, issue, rows_affected, severity, resolution, status)
SELECT 'DQI-03', 'raw', 'DQ02',
       'One measure is split across two columns: euro amounts sit in Observation and counts sit in Number of Accounts',
       (SELECT count(*) FROM clean.mortgage_observation),
       'warning',
       'Clean rule C2 picks the column from the observation type, giving one value column. Rows found: '
       || (SELECT count(*) FILTER (WHERE value_column = 'observation') FROM clean.mortgage_observation) || ' euro rows and '
       || (SELECT count(*) FILTER (WHERE value_column = 'number_of_accounts') FROM clean.mortgage_observation) || ' count rows.',
       'resolved';

INSERT INTO dq.issue_log (issue_id, found_in, rule_ref, issue, rows_affected, severity, resolution, status)
WITH evidence AS (
    SELECT
        (SELECT round((percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(c.value::NUMERIC / p.value - 1)) * 100)::NUMERIC, 1)
           FROM clean.mortgage_observation c
           JOIN clean.mortgage_observation p ON p.quarter_end_date = DATE '2025-12-31' AND p.lender_group = c.lender_group
                AND p.portfolio_code = c.portfolio_code AND p.category = c.category
                AND p.row_position = c.row_position AND p.column_position = c.column_position
          WHERE c.stray_value_ignored AND p.value > 0) AS kept_median,
        (SELECT round((percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(clean.safe_to_bigint(c.stray_value_text)::NUMERIC / p.value - 1)) * 100)::NUMERIC, 0)
           FROM clean.mortgage_observation c
           JOIN clean.mortgage_observation p ON p.quarter_end_date = DATE '2025-12-31' AND p.lender_group = c.lender_group
                AND p.portfolio_code = c.portfolio_code AND p.category = c.category
                AND p.row_position = c.row_position AND p.column_position = c.column_position
          WHERE c.stray_value_ignored AND p.value > 0) AS stray_median
)
SELECT 'DQI-04', 'raw', 'DQ02',
       'Count rows in the 31 March 2026 return also carry a stray euro-style figure in Observation (both value columns filled)',
       (SELECT rows_failed FROM dq.check_result WHERE rule_id = 'DQ02'),
       'warning',
       'Clean rule C4 keeps the Number of Accounts value and ignores the stray one; rows are flagged corrected. Evidence: the kept values move a median of '
       || e.kept_median || ' percent against the previous quarter, whereas using the stray figures would imply a median move of '
       || e.stray_median || ' percent. The stray text is retained in clean.stray_value_text.',
       'resolved'
FROM evidence AS e;

INSERT INTO dq.issue_log (issue_id, found_in, rule_ref, issue, rows_affected, severity, resolution, status)
SELECT 'DQI-05', 'raw', 'DQ06',
       'Reporting dates are the last working day of the quarter, not the calendar quarter end ('
       || (SELECT count(*) FROM clean.reporting_date_map WHERE date_rule = 'working_day_adjusted') || ' distinct dates)',
       (SELECT count(*) FROM clean.mortgage_observation WHERE date_rule = 'working_day_adjusted'),
       'warning',
       'Clean rule C5 maps each to the calendar quarter end so a quarter has one key. The rule accepts a weekday up to 3 days before quarter end.',
       'resolved';

INSERT INTO dq.issue_log (issue_id, found_in, rule_ref, issue, rows_affected, severity, resolution, status)
SELECT 'DQI-06', 'raw', 'DQ06',
       'Two malformed reporting dates: ' || (SELECT string_agg(reporting_date_raw, ' and ' ORDER BY reporting_date_raw) FROM clean.reporting_date_map_repairs),
       (SELECT count(*) FROM clean.mortgage_observation WHERE date_rule = 'repaired_malformed_date'),
       'warning',
       'Mapped to 30 Sep 2025 and 31 Dec 2025 using the evidence stored in clean.reporting_date_map_repairs. This is an inference from the structure of the file. Confirm with the publisher before relying on those two quarters.',
       'accepted';

INSERT INTO dq.issue_log (issue_id, found_in, rule_ref, issue, rows_affected, severity, resolution, status)
SELECT 'DQI-07', 'mart', 'DQ21',
       'Core measures missing for a segment and quarter: ' || (SELECT detail FROM dq.check_result WHERE rule_id = 'DQ21'),
       (SELECT rows_failed FROM dq.check_result WHERE rule_id = 'DQ21'),
       'warning',
       'Not imputed. KPIs that need a missing measure (arrears total, total outstanding) are blank for that segment and quarter. Dashboards must use the latest complete quarter for headline figures.',
       'accepted';

INSERT INTO dq.issue_log (issue_id, found_in, rule_ref, issue, rows_affected, severity, resolution, status)
SELECT 'DQI-08', 'mart', 'DQ16',
       'Legal status counts do not add up to total accounts in arrears for: '
       || (SELECT string_agg(d.quarter_label || ' ' || lg.lender_group_name || ' ' || p.portfolio_code
                             || ' (difference ' || v.difference || ')', '; ' ORDER BY d.quarter_sort)
             FROM dq.v_legal_status_vs_arrears_total AS v
             JOIN mart.dim_date AS d USING (date_key)
             JOIN mart.dim_lender_group AS lg USING (lender_group_key)
             JOIN mart.dim_portfolio AS p USING (portfolio_key)
            WHERE v.difference <> 0),
       (SELECT rows_failed FROM dq.check_result WHERE rule_id = 'DQ16'),
       'warning',
       'Source inconsistency. Values kept as published. No KPI is built on the sum of legal status counts, and the arrears total from the Arrears category is used instead.',
       'accepted';

INSERT INTO dq.issue_log (issue_id, found_in, rule_ref, issue, rows_affected, severity, resolution, status)
SELECT 'DQI-09', 'mart', 'DQ15',
       'Euro totals differ from the sum of their buckets by up to '
       || (SELECT max(abs(difference)) FROM dq.v_arrears_total_vs_buckets WHERE metric_column IN (2, 3)) || ' thousand euro',
       (SELECT count(*) FROM dq.v_arrears_total_vs_buckets WHERE metric_column IN (2, 3) AND difference <> 0),
       'info',
       'Rounding: each figure is published to the nearest thousand. DQ15 allows (buckets + 1) / 2 thousand and every comparison is inside it. Account counts reconcile exactly (DQ14).',
       'accepted';

INSERT INTO dq.issue_log (issue_id, found_in, rule_ref, issue, rows_affected, severity, resolution, status)
SELECT 'DQI-10', 'mart', 'design',
       'Arrears bucket scheme changes over time: 3 buckets to Q2 2012, 5 buckets to Q2 2019, 7 buckets from Q3 2019',
       (SELECT count(*) FROM mart.fact_mortgage_measure f JOIN mart.dim_measure dm USING (measure_key)
         WHERE dm.category = 'Arrears' AND dm.source_row_position IN (5, 8)),
       'warning',
       'dim_measure.harmonised_bucket maps every scheme to Up to 90 days, 91 to 180 days and Over 180 days, so trends are comparable. is_total stops totals being added to buckets. DQ14 and DQ15 prove no bucket is double counted or missing. Rows counted are the retired-scheme buckets.',
       'resolved';

INSERT INTO dq.issue_log (issue_id, found_in, rule_ref, issue, rows_affected, severity, resolution, status)
SELECT 'DQI-11', 'mart', 'DQ23',
       'Possessions at the start of a quarter differ from the previous quarter end in '
       || (SELECT rows_failed FROM dq.check_result WHERE rule_id = 'DQ23') || ' of '
       || (SELECT rows_tested FROM dq.check_result WHERE rule_id = 'DQ23') || ' comparisons',
       (SELECT rows_failed FROM dq.check_result WHERE rule_id = 'DQ23'),
       'info',
       'Observation only. The publisher may restate prior figures or change definitions, so no rule or KPI relies on continuity. Recorded for transparency.',
       'monitor';

/* Stop the pipeline on any error-level failure or reconciliation mismatch. */
DO $$
DECLARE
    n_fail INTEGER;
    n_mismatch INTEGER;
    n_checks INTEGER;
BEGIN
    SELECT count(*) INTO n_fail     FROM dq.check_result   WHERE run_label = 'pipeline_run' AND status = 'fail';
    SELECT count(*) INTO n_mismatch FROM dq.reconciliation WHERE status = 'mismatch';
    SELECT count(*) INTO n_checks   FROM dq.check_result   WHERE run_label = 'pipeline_run';
    IF n_fail > 0 THEN
        RAISE EXCEPTION 'DATA QUALITY STOP: % error-level rule(s) failed. Query dq.check_result.', n_fail;
    END IF;
    IF n_mismatch > 0 THEN
        RAISE EXCEPTION 'RECONCILIATION STOP: % reconciliation step(s) do not match. Query dq.reconciliation.', n_mismatch;
    END IF;
    RAISE NOTICE 'Pipeline gate passed: % rules run, 0 errors, 0 reconciliation mismatches.', n_checks;
END $$;

/* Exports for the repository and for the Power BI data quality page. */
\copy (SELECT issue_id, found_in, rule_ref, issue, rows_affected, severity, resolution, status FROM dq.issue_log ORDER BY issue_id) TO 'docs/dq_issue_tracker.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

SELECT rule_id, status, rows_tested, rows_failed, pct_failed FROM dq.check_result WHERE run_label = 'pipeline_run' ORDER BY rule_id;
SELECT status, count(*) AS reconciliation_steps FROM dq.reconciliation GROUP BY status;
