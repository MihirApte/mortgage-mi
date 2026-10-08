/*
  11_dq_selftest.sql
  Purpose : Prove the data quality rules can actually fail. A check that has never been seen
            to fail proves nothing, because it may be testing the wrong thing.

  Method
    1. Open a transaction and run all rules on the real data (baseline).
    2. Corrupt the data in specific ways, one corruption per rule.
    3. Run all rules again and require that every targeted rule reports MORE failures than in the baseline.
    4. Roll the transaction back, so the real data is never changed.
    5. Confirm the rollback left the data exactly as it was.

  Rules DQ10 (duplicate fact grain) and DQ19 (orphan fact keys) cannot be corrupted through
  normal updates because the database blocks the change. Section B proves the database
  constraints themselves reject those corruptions.
*/

DROP TABLE IF EXISTS pg_temp.selftest_before;
CREATE TEMP TABLE selftest_before AS
SELECT count(*) AS fact_rows_before, COALESCE(sum(value), 0) AS fact_value_before FROM mart.fact_mortgage_measure;

BEGIN;

/* A. Baseline on real data */
CALL dq.run_checks('selftest_baseline');

/* Corruptions: one per rule. Row ids 1 to 12 and the Q4 2025 key combinations exist in the real data. */
UPDATE raw.cbi_mortgage_arrears_open_data SET category = NULL                              WHERE raw_row_id = 1;   /* DQ01 */
UPDATE raw.cbi_mortgage_arrears_open_data SET observation = NULL, number_of_accounts = NULL WHERE raw_row_id = 2;   /* DQ02 */
UPDATE clean.mortgage_observation          SET value = NULL                                WHERE raw_row_id = 3;   /* DQ03 */
UPDATE raw.cbi_mortgage_arrears_open_data SET observation = '12x'
 WHERE raw_row_id = (SELECT min(raw_row_id) FROM raw.cbi_mortgage_arrears_open_data WHERE observation IS NOT NULL); /* DQ04 */
UPDATE raw.cbi_mortgage_arrears_open_data SET reporting_date = '31/02/2020'                WHERE raw_row_id = 5;   /* DQ05 */
UPDATE raw.cbi_mortgage_arrears_open_data SET reporting_date = '15/05/2020'                WHERE raw_row_id = 6;   /* DQ06 */
UPDATE raw.cbi_mortgage_arrears_open_data SET entity_group = 'Bank'                        WHERE raw_row_id = 7;   /* DQ07 */
INSERT INTO raw.cbi_mortgage_arrears_open_data (reporting_date, entity_group, format_code, category, row_position,
                                                column_position, row_label, observation_type, observation, number_of_accounts)
SELECT reporting_date, entity_group, format_code, category, row_position, column_position, row_label,
       observation_type, observation, number_of_accounts
FROM raw.cbi_mortgage_arrears_open_data WHERE raw_row_id = 8;                                                      /* DQ08 */

CREATE TEMP TABLE t_dup AS SELECT * FROM clean.mortgage_observation WHERE raw_row_id = 9;
UPDATE t_dup SET raw_row_id = 900001;
INSERT INTO clean.mortgage_observation SELECT * FROM t_dup;                                                         /* DQ09 */

UPDATE clean.mortgage_observation SET value = -5 WHERE raw_row_id = 10;                                             /* DQ11 */

/* Fact-level corruptions use dim lookups so they do not depend on key numbering. */
UPDATE mart.fact_mortgage_measure f SET value = 999999999999
 FROM mart.dim_measure dm
 WHERE dm.measure_key = f.measure_key AND dm.category = 'Arrears' AND dm.source_row_position = 3 AND dm.source_column_position = 3
   AND f.date_key = 20251231 AND f.lender_group_key = 1 AND f.portfolio_key = 1;                                    /* DQ12 */

UPDATE mart.fact_mortgage_measure f SET value = 999999999
 FROM mart.dim_measure dm
 WHERE dm.measure_key = f.measure_key AND dm.category = 'Arrears' AND dm.source_row_position = 2 AND dm.source_column_position = 1
   AND f.date_key = 20251231 AND f.lender_group_key = 1 AND f.portfolio_key = 1;                                    /* DQ13 */

UPDATE mart.fact_mortgage_measure f SET value = f.value + 10
 FROM mart.dim_measure dm
 WHERE dm.measure_key = f.measure_key AND dm.category = 'Arrears' AND dm.source_row_position = 2 AND dm.source_column_position = 1
   AND f.date_key = 20251231 AND f.lender_group_key = 2 AND f.portfolio_key = 2;                                    /* DQ14 */

UPDATE mart.fact_mortgage_measure f SET value = f.value + 1000000
 FROM mart.dim_measure dm
 WHERE dm.measure_key = f.measure_key AND dm.category = 'Arrears' AND dm.source_row_position = 2 AND dm.source_column_position = 2
   AND f.date_key = 20251231 AND f.lender_group_key = 1 AND f.portfolio_key = 2;                                    /* DQ15 */

UPDATE mart.fact_mortgage_measure f SET value = f.value + 1
 FROM mart.dim_measure dm
 WHERE dm.measure_key = f.measure_key AND dm.category = 'Legal Status of Accounts in Arrears' AND dm.source_row_position = 12
   AND dm.source_column_position = 1 AND f.date_key = 20251231 AND f.lender_group_key = 1 AND f.portfolio_key = 1; /* DQ16 */

CREATE TEMP TABLE t_pos AS SELECT * FROM clean.mortgage_observation WHERE raw_row_id = 11;
UPDATE t_pos SET raw_row_id = 900002, row_position = 99;
INSERT INTO clean.mortgage_observation SELECT * FROM t_pos;                                                         /* DQ17 */

CREATE TEMP TABLE t_dt AS SELECT * FROM clean.mortgage_observation WHERE raw_row_id = 12;
UPDATE t_dt SET raw_row_id = 900003, quarter_end_date = DATE '1999-12-31';
INSERT INTO clean.mortgage_observation SELECT * FROM t_dt;                                                          /* DQ18 */

UPDATE mart.fact_mortgage_measure SET source_raw_row_id = 99999999
 WHERE (date_key, lender_group_key, portfolio_key, measure_key) =
       (SELECT date_key, lender_group_key, portfolio_key, measure_key FROM mart.fact_mortgage_measure
         WHERE date_key = 20251231 ORDER BY measure_key LIMIT 1);                                                   /* DQ20 */

DELETE FROM mart.fact_mortgage_measure f
 USING mart.dim_measure dm
 WHERE dm.measure_key = f.measure_key AND dm.category = 'Arrears' AND dm.source_row_position = 2 AND dm.source_column_position = 1
   AND f.date_key = 20251231 AND f.lender_group_key = 2 AND f.portfolio_key = 1;                                    /* DQ21 */

DELETE FROM mart.fact_mortgage_measure WHERE date_key = 20100331;                                                   /* DQ22 */

UPDATE mart.fact_mortgage_measure f SET value = f.value + 1
 FROM mart.dim_measure dm
 WHERE dm.measure_key = f.measure_key AND dm.category = 'Repossessions' AND dm.source_row_position = 20
   AND f.date_key = 20251231 AND f.lender_group_key = 1 AND f.portfolio_key = 1;                                    /* DQ23 */

/* B. Run again on the corrupted data, then compare with the baseline. */
CALL dq.run_checks('selftest_corrupted');

DO $$
DECLARE
    r RECORD;
    n_detected INTEGER := 0;
    n_missed   INTEGER := 0;
    targeted   TEXT[] := ARRAY['DQ01','DQ02','DQ03','DQ04','DQ05','DQ06','DQ07','DQ08','DQ09','DQ11','DQ12','DQ13',
                               'DQ14','DQ15','DQ16','DQ17','DQ18','DQ20','DQ21','DQ22','DQ23'];
BEGIN
    FOR r IN
        SELECT b.rule_id, b.rows_failed AS baseline_failed, c.rows_failed AS corrupted_failed
        FROM dq.check_result AS b
        JOIN dq.check_result AS c ON c.rule_id = b.rule_id AND c.run_label = 'selftest_corrupted'
        WHERE b.run_label = 'selftest_baseline' AND b.rule_id = ANY (targeted)
        ORDER BY b.rule_id
    LOOP
        IF r.corrupted_failed > r.baseline_failed THEN
            n_detected := n_detected + 1;
            RAISE NOTICE 'SELFTEST detected %: failures went from % to %', r.rule_id, r.baseline_failed, r.corrupted_failed;
        ELSE
            n_missed := n_missed + 1;
            RAISE WARNING 'SELFTEST MISSED %: failures stayed at % (baseline %)', r.rule_id, r.corrupted_failed, r.baseline_failed;
        END IF;
    END LOOP;
    IF n_missed > 0 OR n_detected <> array_length(targeted, 1) THEN
        RAISE EXCEPTION 'SELFTEST FAILED: % rule(s) did not detect their corruption (detected %, expected %)',
                        n_missed, n_detected, array_length(targeted, 1);
    END IF;
    RAISE NOTICE 'SELFTEST passed: all % targeted rules detected their corruption', n_detected;
END $$;

ROLLBACK;

/* C. Database constraints must reject what DQ10 and DQ19 would otherwise have to catch. */
DO $$
DECLARE
    v_key RECORD;
BEGIN
    SELECT * INTO v_key FROM mart.fact_mortgage_measure LIMIT 1;

    BEGIN
        INSERT INTO mart.fact_mortgage_measure VALUES (v_key.date_key, v_key.lender_group_key, v_key.portfolio_key,
                                                       v_key.measure_key, 1, 888888888);
        RAISE EXCEPTION 'CONSTRAINT TEST FAILED: duplicate grain was accepted';
    EXCEPTION WHEN unique_violation THEN
        RAISE NOTICE 'CONSTRAINT test passed: duplicate grain rejected by the primary key (covers DQ10)';
    END;

    BEGIN
        INSERT INTO mart.fact_mortgage_measure VALUES (99999999, 1, 1, v_key.measure_key, 1, 888888889);
        RAISE EXCEPTION 'CONSTRAINT TEST FAILED: orphan date key was accepted';
    EXCEPTION WHEN foreign_key_violation THEN
        RAISE NOTICE 'CONSTRAINT test passed: orphan dimension key rejected by the foreign key (covers DQ19)';
    END;

    BEGIN
        UPDATE mart.fact_mortgage_measure SET value = -1
         WHERE (date_key, lender_group_key, portfolio_key, measure_key) =
               (v_key.date_key, v_key.lender_group_key, v_key.portfolio_key, v_key.measure_key);
        RAISE EXCEPTION 'CONSTRAINT TEST FAILED: negative value was accepted';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'CONSTRAINT test passed: negative value rejected by the check constraint';
    END;
END $$;

/* D. Prove the rollback restored the real data exactly. */
DO $$
DECLARE
    n_rows BIGINT;
    v_sum  BIGINT;
    n_leftover INTEGER;
    n_raw BIGINT;
BEGIN
    SELECT count(*), sum(value) INTO n_rows, v_sum FROM mart.fact_mortgage_measure;
    SELECT count(*) INTO n_leftover FROM dq.check_result WHERE run_label LIKE 'selftest%';
    SELECT count(*) INTO n_raw FROM raw.cbi_mortgage_arrears_open_data;
    IF n_rows <> (SELECT fact_rows_before FROM selftest_before) OR v_sum <> (SELECT fact_value_before FROM selftest_before)
       OR n_leftover <> 0 OR n_raw <> 19199 THEN
        RAISE EXCEPTION 'ROLLBACK CHECK FAILED: data differs from before the self-test';
    END IF;
    RAISE NOTICE 'ROLLBACK check passed: fact rows %, value total %, raw rows % are unchanged', n_rows, v_sum, n_raw;
END $$;
