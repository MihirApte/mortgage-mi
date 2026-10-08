/*
  12_day2_controls.sql
  Purpose : Compare the mart with control totals computed by a separate tool.

  The constants below come from scripts/independent_controls.py, which reads the CSV with plain
  Python and shares no code with the SQL pipeline. If you change the source file, rerun that
  script and update the constants. The run stops on any mismatch.

  Control values as produced by the script:
    rows 19199, value_total 15395850005, stray_value_rows 70, euro_rows 10832, count_rows 8367
*/

DO $$ BEGIN PERFORM dq.log_recon('Independent control (Python)', 'row count', 'Python reading the CSV', 19199,
                    'mart fact', (SELECT count(*) FROM mart.fact_mortgage_measure),
                    'Valid only while no row is quarantined'); END $$;

DO $$ BEGIN PERFORM dq.log_recon('Independent control (Python)', 'sum of all values', 'Python reading the CSV', 15395850005,
                    'mart fact', (SELECT sum(value) FROM mart.fact_mortgage_measure),
                    'Python picks the value column with its own code and sums the digits'); END $$;

DO $$ BEGIN PERFORM dq.log_recon('Independent control (Python)', 'rows with a stray value', 'Python reading the CSV', 70,
                    'clean flag stray_value_ignored', (SELECT count(*) FROM clean.mortgage_observation WHERE stray_value_ignored)); END $$;

DO $$ BEGIN PERFORM dq.log_recon('Independent control (Python)', 'euro metric rows', 'Python reading the CSV', 10832,
                    'mart fact (EUR thousands)',
                    (SELECT count(*) FROM mart.fact_mortgage_measure f JOIN mart.dim_measure dm USING (measure_key) WHERE dm.unit = 'EUR thousands')); END $$;

DO $$ BEGIN PERFORM dq.log_recon('Independent control (Python)', 'count metric rows', 'Python reading the CSV', 8367,
                    'mart fact (accounts and properties)',
                    (SELECT count(*) FROM mart.fact_mortgage_measure f JOIN mart.dim_measure dm USING (measure_key) WHERE dm.unit <> 'EUR thousands')); END $$;

DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN
        SELECT v.category AS k, v.n AS a, COALESCE(f.n, 0) AS b
        FROM (VALUES ('Arrears', 4913), ('Borrower co-operation status', 1512), ('Duration in Legal Proceedings', 648),
                     ('Legal Status of Accounts in Arrears', 1608), ('Repossessions', 1145), ('Restructures - By Type', 7019),
                     ('Restructures - Overview', 1864), ('Total Outstanding', 490)) AS v (category, n)
        LEFT JOIN (SELECT dm.category, count(*) AS n FROM mart.fact_mortgage_measure fm JOIN mart.dim_measure dm USING (measure_key)
                   GROUP BY dm.category) AS f USING (category)
        ORDER BY v.category
    LOOP
        PERFORM dq.log_recon('Independent control (Python)', rec.k, 'Python reading the CSV', rec.a, 'mart fact', rec.b);
    END LOOP;
END $$;

DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN
        SELECT v.segment AS k, v.n AS a, COALESCE(f.n, 0) AS b
        FROM (VALUES ('Banks BTL', 3602), ('Banks PDH', 5952), ('Non-Banks BTL', 3573), ('Non-Banks PDH', 6072)) AS v (segment, n)
        LEFT JOIN (SELECT lg.lender_group_name || ' ' || p.portfolio_code AS segment, count(*) AS n
                   FROM mart.fact_mortgage_measure fm
                   JOIN mart.dim_lender_group lg USING (lender_group_key)
                   JOIN mart.dim_portfolio p USING (portfolio_key)
                   GROUP BY 1) AS f USING (segment)
        ORDER BY v.segment
    LOOP
        PERFORM dq.log_recon('Independent control (Python)', rec.k, 'Python reading the CSV', rec.a, 'mart fact', rec.b);
    END LOOP;
END $$;

DO $$
DECLARE
    n_bad INTEGER;
    n_all INTEGER;
BEGIN
    SELECT count(*) FILTER (WHERE status = 'mismatch'), count(*) INTO n_bad, n_all FROM dq.reconciliation;
    IF n_bad > 0 THEN
        RAISE EXCEPTION 'CONTROL TOTALS FAILED: % of % reconciliation steps do not match', n_bad, n_all;
    END IF;
    RAISE NOTICE 'Control totals passed: all % reconciliation steps match, including the independent Python controls', n_all;
END $$;
