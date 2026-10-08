/*
  13_clean_quarantine_test.sql
  Purpose : The real data has zero quarantined rows, so the quarantine rules in the clean
            layer never fire on it. This test proves they work anyway.

  Method: inside a transaction, corrupt six raw rows (one corruption each), rebuild the clean
  layer with the real build script, assert that each corrupted row is quarantined for the
  expected reason and that nothing else changed, then roll everything back.
*/

DROP TABLE IF EXISTS pg_temp.quarantine_before;
CREATE TEMP TABLE quarantine_before AS
SELECT count(*) FILTER (WHERE dq_status = 'valid')       AS n_valid,
       count(*) FILTER (WHERE dq_status = 'corrected')   AS n_corrected,
       count(*) FILTER (WHERE dq_status = 'quarantined') AS n_quarantined
FROM clean.mortgage_observation;

BEGIN;

UPDATE raw.cbi_mortgage_arrears_open_data SET observation = '12x', number_of_accounts = '12x' WHERE raw_row_id = 1;
UPDATE raw.cbi_mortgage_arrears_open_data SET entity_group = 'Bank'                            WHERE raw_row_id = 2;
UPDATE raw.cbi_mortgage_arrears_open_data SET format_code = 'XYZ'                              WHERE raw_row_id = 3;
UPDATE raw.cbi_mortgage_arrears_open_data SET reporting_date = '31/02/2020'                    WHERE raw_row_id = 4;
UPDATE raw.cbi_mortgage_arrears_open_data SET row_position = 'abc'                             WHERE raw_row_id = 5;
INSERT INTO raw.cbi_mortgage_arrears_open_data (reporting_date, entity_group, format_code, category, row_position,
                                                column_position, row_label, observation_type, observation, number_of_accounts)
SELECT reporting_date, entity_group, format_code, category, row_position, column_position, row_label,
       observation_type, observation, number_of_accounts
FROM raw.cbi_mortgage_arrears_open_data WHERE raw_row_id = 8;

\i sql/06_clean_build.sql

DO $$
DECLARE
    v_dup_id BIGINT := (SELECT max(raw_row_id) FROM raw.cbi_mortgage_arrears_open_data);
    n_q INTEGER;
    r RECORD;
BEGIN
    FOR r IN
        SELECT * FROM (VALUES
            (1::BIGINT,   'value missing or not numeric'),
            (2::BIGINT,   'unknown lender group'),
            (3::BIGINT,   'unknown portfolio code'),
            (4::BIGINT,   'date could not be mapped to a quarter end'),
            (5::BIGINT,   'position is not a number'),
            (v_dup_id,    'duplicate of an earlier row at the same grain')
        ) AS t (raw_row_id, expected_reason)
    LOOP
        IF NOT EXISTS (SELECT 1 FROM clean.mortgage_observation c
                        WHERE c.raw_row_id = r.raw_row_id AND c.dq_status = 'quarantined' AND c.dq_reason = r.expected_reason) THEN
            RAISE EXCEPTION 'QUARANTINE TEST FAILED: raw row % was not quarantined with reason "%"', r.raw_row_id, r.expected_reason;
        END IF;
        RAISE NOTICE 'QUARANTINE test passed: raw row % quarantined as "%"', r.raw_row_id, r.expected_reason;
    END LOOP;

    SELECT count(*) INTO n_q FROM clean.mortgage_observation WHERE dq_status = 'quarantined';
    IF n_q <> 6 THEN
        RAISE EXCEPTION 'QUARANTINE TEST FAILED: expected exactly 6 quarantined rows, found %', n_q;
    END IF;
    RAISE NOTICE 'QUARANTINE test passed: exactly 6 rows quarantined and none of the untouched rows were affected';
END $$;

ROLLBACK;

DO $$
DECLARE
    b RECORD;
    a RECORD;
BEGIN
    SELECT * INTO b FROM quarantine_before;
    SELECT count(*) FILTER (WHERE dq_status = 'valid') AS n_valid,
           count(*) FILTER (WHERE dq_status = 'corrected') AS n_corrected,
           count(*) FILTER (WHERE dq_status = 'quarantined') AS n_quarantined,
           (SELECT count(*) FROM raw.cbi_mortgage_arrears_open_data) AS n_raw
      INTO a FROM clean.mortgage_observation;
    IF a.n_valid <> b.n_valid OR a.n_corrected <> b.n_corrected OR a.n_quarantined <> b.n_quarantined OR a.n_raw <> 19199 THEN
        RAISE EXCEPTION 'ROLLBACK CHECK FAILED: clean or raw differs from before the quarantine test';
    END IF;
    RAISE NOTICE 'ROLLBACK check passed: clean is back to % valid, % corrected, % quarantined and raw has % rows',
                 a.n_valid, a.n_corrected, a.n_quarantined, a.n_raw;
END $$;
