/*
  05_day1_checks.sql
  Purpose : Prove the raw load is complete and untouched, and the reference dimensions are right.
  Behaviour: each check raises an error and stops the run if it fails, so a green run means every check passed.

  Control totals below were measured independently of SQL, by profiling the CSV with Python
  (pandas) before loading. Checking SQL against a second tool is what makes them controls.
    data rows in file          : 19199 (file has 19200 lines including the header)
    Observation empty cells    : 8297
    Number of Accounts empty   : 10832
*/

DO $$
DECLARE
    n_rows        BIGINT;
    n_min         BIGINT;
    n_max         BIGINT;
    n_obs_null    BIGINT;
    n_acc_null    BIGINT;
    n_euro        BIGINT;
    n_bad_char    BIGINT;
    n_padded      BIGINT;
BEGIN
    SELECT count(*), min(raw_row_id), max(raw_row_id) INTO n_rows, n_min, n_max
    FROM raw.cbi_mortgage_arrears_open_data;

    IF n_rows <> 19199 THEN
        RAISE EXCEPTION 'CHECK 1 FAILED: expected 19199 raw rows, found %', n_rows;
    END IF;
    RAISE NOTICE 'CHECK 1 passed: raw row count = % (matches file)', n_rows;

    IF n_min <> 1 OR n_max <> n_rows THEN
        RAISE EXCEPTION 'CHECK 2 FAILED: raw_row_id is not contiguous 1..% (min %, max %)', n_rows, n_min, n_max;
    END IF;
    RAISE NOTICE 'CHECK 2 passed: raw_row_id runs 1..% with no gaps', n_rows;

    SELECT count(*) FILTER (WHERE observation IS NULL),
           count(*) FILTER (WHERE number_of_accounts IS NULL)
    INTO n_obs_null, n_acc_null
    FROM raw.cbi_mortgage_arrears_open_data;

    IF n_obs_null <> 8297 OR n_acc_null <> 10832 THEN
        RAISE EXCEPTION 'CHECK 3 FAILED: empty-cell counts differ from control (observation %, accounts %)', n_obs_null, n_acc_null;
    END IF;
    RAISE NOTICE 'CHECK 3 passed: empty cells match control totals (observation %, accounts %)', n_obs_null, n_acc_null;

    SELECT count(*) FILTER (WHERE observation_type LIKE '%' || chr(8364) || '%'),
           count(*) FILTER (WHERE observation_type LIKE '%' || chr(65533) || '%')
    INTO n_euro, n_bad_char
    FROM raw.cbi_mortgage_arrears_open_data;

    IF n_euro = 0 OR n_bad_char <> 0 THEN
        RAISE EXCEPTION 'CHECK 4 FAILED: euro sign not decoded correctly (euro rows %, replacement chars %)', n_euro, n_bad_char;
    END IF;
    RAISE NOTICE 'CHECK 4 passed: euro sign decoded in % rows, 0 replacement characters', n_euro;

    SELECT count(*) INTO n_padded
    FROM raw.cbi_mortgage_arrears_open_data
    WHERE number_of_accounts <> btrim(number_of_accounts) OR observation <> btrim(observation);

    IF n_padded = 0 THEN
        RAISE EXCEPTION 'CHECK 5 FAILED: no padded values found, so the raw layer may have been trimmed';
    END IF;
    RAISE NOTICE 'CHECK 5 passed: % raw values still carry source padding, so raw is untouched', n_padded;
END $$;

DO $$
DECLARE
    n_quarters   INTEGER;
    n_no_prior   INTEGER;
    first_q      DATE;
    last_q       DATE;
    bad_ends     INTEGER;
BEGIN
    SELECT count(*), count(*) FILTER (WHERE prior_quarter_key IS NULL), min(quarter_end_date), max(quarter_end_date)
    INTO n_quarters, n_no_prior, first_q, last_q
    FROM mart.dim_date;

    IF n_quarters <> 67 OR first_q <> DATE '2009-09-30' OR last_q <> DATE '2026-03-31' THEN
        RAISE EXCEPTION 'CHECK 6 FAILED: dim_date should hold 67 quarters from 2009-09-30 to 2026-03-31, found % from % to %', n_quarters, first_q, last_q;
    END IF;
    RAISE NOTICE 'CHECK 6 passed: dim_date has % quarters, % to %', n_quarters, first_q, last_q;

    IF n_no_prior <> 1 THEN
        RAISE EXCEPTION 'CHECK 7 FAILED: exactly one quarter should have no prior quarter, found %', n_no_prior;
    END IF;
    RAISE NOTICE 'CHECK 7 passed: prior_quarter_key is populated for every quarter except the first';

    SELECT count(*) INTO bad_ends
    FROM mart.dim_date
    WHERE (quarter_end_date + 1) <> (date_trunc('quarter', quarter_end_date) + INTERVAL '3 months')::DATE;

    IF bad_ends <> 0 THEN
        RAISE EXCEPTION 'CHECK 8 FAILED: % dim_date rows are not true calendar quarter ends', bad_ends;
    END IF;
    RAISE NOTICE 'CHECK 8 passed: every dim_date row is a true calendar quarter end';
END $$;

/* Summary of every object created, for the run log. */
SELECT 'raw.cbi_mortgage_arrears_open_data' AS object_name, count(*) AS row_count FROM raw.cbi_mortgage_arrears_open_data
UNION ALL SELECT 'mart.dim_date',          count(*) FROM mart.dim_date
UNION ALL SELECT 'mart.dim_lender_group',  count(*) FROM mart.dim_lender_group
UNION ALL SELECT 'mart.dim_portfolio',     count(*) FROM mart.dim_portfolio
UNION ALL SELECT 'mart.dim_measure',       count(*) FROM mart.dim_measure
UNION ALL SELECT 'mart.fact_mortgage_measure', count(*) FROM mart.fact_mortgage_measure;
