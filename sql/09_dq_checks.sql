/*
  09_dq_checks.sql
  Purpose : The data quality checks, written once as a procedure so they can be run on the
            real data (10_dq_run.sql) and on deliberately corrupted data (11_dq_selftest.sql).

  Views first: several rules compare a total with its components or two related measures.
  Putting that comparison in a view means the rule, the issue tracker and the UAT script
  on Day 4 all use the same definition.
*/

/* Arrears total versus the sum of its buckets, per quarter, lender group, portfolio and metric column.
   Within one quarter only one bucket scheme is present, so summing every non-total row is safe. */
CREATE OR REPLACE VIEW dq.v_arrears_total_vs_buckets AS
WITH base AS (
    SELECT f.date_key, f.lender_group_key, f.portfolio_key,
           dm.source_column_position AS metric_column,
           dm.source_row_position    AS row_position,
           f.value
    FROM mart.fact_mortgage_measure AS f
    JOIN mart.dim_measure AS dm USING (measure_key)
    WHERE dm.category = 'Arrears'
)
SELECT  t.date_key, t.lender_group_key, t.portfolio_key, t.metric_column,
        t.value   AS total_value,
        l.leaf_sum,
        l.n_leaf,
        t.value - l.leaf_sum AS difference
FROM (SELECT * FROM base WHERE row_position = 2) AS t
JOIN (SELECT date_key, lender_group_key, portfolio_key, metric_column,
             sum(value) AS leaf_sum, count(*) AS n_leaf
      FROM base WHERE row_position <> 2
      GROUP BY date_key, lender_group_key, portfolio_key, metric_column) AS l
  USING (date_key, lender_group_key, portfolio_key, metric_column);

/* Arrears amount against the balance of the same line item. */
CREATE OR REPLACE VIEW dq.v_arrears_amount_vs_balance AS
SELECT  f.date_key, f.lender_group_key, f.portfolio_key, dm.category, dm.source_row_position AS row_position,
        max(f.value) FILTER (WHERE dm.source_column_position = 2) AS balance_value,
        max(f.value) FILTER (WHERE dm.source_column_position = 3) AS arrears_value
FROM mart.fact_mortgage_measure AS f
JOIN mart.dim_measure AS dm USING (measure_key)
WHERE dm.unit = 'EUR thousands'
GROUP BY f.date_key, f.lender_group_key, f.portfolio_key, dm.category, dm.source_row_position
HAVING max(f.value) FILTER (WHERE dm.source_column_position = 2) IS NOT NULL
   AND max(f.value) FILTER (WHERE dm.source_column_position = 3) IS NOT NULL;

/* Total in arrears against total outstanding, for accounts (column 1) and balance (column 2). */
CREATE OR REPLACE VIEW dq.v_arrears_vs_outstanding AS
SELECT  a.date_key, a.lender_group_key, a.portfolio_key, a.metric_column,
        a.value AS arrears_total, o.value AS outstanding_total
FROM (SELECT f.date_key, f.lender_group_key, f.portfolio_key, dm.source_column_position AS metric_column, f.value
      FROM mart.fact_mortgage_measure AS f JOIN mart.dim_measure AS dm USING (measure_key)
      WHERE dm.category = 'Arrears' AND dm.source_row_position = 2 AND dm.source_column_position IN (1, 2)) AS a
JOIN (SELECT f.date_key, f.lender_group_key, f.portfolio_key, dm.source_column_position AS metric_column, f.value
      FROM mart.fact_mortgage_measure AS f JOIN mart.dim_measure AS dm USING (measure_key)
      WHERE dm.category = 'Total Outstanding') AS o
  USING (date_key, lender_group_key, portfolio_key, metric_column);

/* Legal status account counts against total accounts in arrears. */
CREATE OR REPLACE VIEW dq.v_legal_status_vs_arrears_total AS
SELECT  l.date_key, l.lender_group_key, l.portfolio_key, l.legal_sum, t.arrears_total, l.legal_sum - t.arrears_total AS difference
FROM (SELECT f.date_key, f.lender_group_key, f.portfolio_key, sum(f.value) AS legal_sum
      FROM mart.fact_mortgage_measure AS f JOIN mart.dim_measure AS dm USING (measure_key)
      WHERE dm.category = 'Legal Status of Accounts in Arrears' AND dm.source_column_position = 1
      GROUP BY f.date_key, f.lender_group_key, f.portfolio_key) AS l
JOIN (SELECT f.date_key, f.lender_group_key, f.portfolio_key, f.value AS arrears_total
      FROM mart.fact_mortgage_measure AS f JOIN mart.dim_measure AS dm USING (measure_key)
      WHERE dm.category = 'Arrears' AND dm.source_row_position = 2 AND dm.source_column_position = 1) AS t
  USING (date_key, lender_group_key, portfolio_key);

/* The five core measures every segment and quarter should have. One row per expected cell. */
CREATE OR REPLACE VIEW dq.v_core_measure_coverage AS
WITH segments AS (
    SELECT DISTINCT date_key, lender_group_key, portfolio_key FROM mart.fact_mortgage_measure
),
core AS (
    SELECT measure_key, category, source_row_position, source_column_position
    FROM mart.dim_measure
    WHERE (category = 'Arrears' AND source_row_position = 2 AND source_column_position IN (1, 2, 3))
       OR (category = 'Total Outstanding' AND source_row_position = 1 AND source_column_position IN (1, 2))
)
SELECT  s.date_key, s.lender_group_key, s.portfolio_key, c.measure_key, c.category,
        c.source_row_position, c.source_column_position,
        (f.measure_key IS NOT NULL) AS is_present
FROM segments AS s
CROSS JOIN core AS c
LEFT JOIN mart.fact_mortgage_measure AS f
       ON f.date_key = s.date_key AND f.lender_group_key = s.lender_group_key
      AND f.portfolio_key = s.portfolio_key AND f.measure_key = c.measure_key;

/* Possessions at the start of a quarter against the end of the previous quarter. */
CREATE OR REPLACE VIEW dq.v_possession_continuity AS
SELECT  cur.date_key, cur.lender_group_key, cur.portfolio_key,
        cur.value AS start_of_quarter, prv.value AS prior_quarter_end
FROM (SELECT f.date_key, f.lender_group_key, f.portfolio_key, f.value
      FROM mart.fact_mortgage_measure AS f JOIN mart.dim_measure AS dm USING (measure_key)
      WHERE dm.category = 'Repossessions' AND dm.source_row_position = 20) AS cur
JOIN mart.dim_date AS d ON d.date_key = cur.date_key
JOIN (SELECT f.date_key, f.lender_group_key, f.portfolio_key, f.value
      FROM mart.fact_mortgage_measure AS f JOIN mart.dim_measure AS dm USING (measure_key)
      WHERE dm.category = 'Repossessions' AND dm.source_row_position = 24) AS prv
  ON prv.date_key = d.prior_quarter_key
 AND prv.lender_group_key = cur.lender_group_key AND prv.portfolio_key = cur.portfolio_key;

/* The procedure: runs every rule and logs one row per rule under the given run label. */
DROP ROUTINE IF EXISTS dq.run_checks(TEXT);

CREATE OR REPLACE PROCEDURE dq.run_checks(p_run TEXT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_types TEXT[] := ARRAY[
        'Number',
        'Balance ' || chr(8364) || ' (000)',
        'Arrears ' || chr(8364) || ' (000)',
        'Number, In Arrears, Restruc.',
        'Number, Not Restruc., Co-operating',
        'Not Co-operating, Legal Proceed. Initiate',
        'Not Co-operating, Legal Proceed. Not Initiate'];
BEGIN
    /* DQ01 Key fields present */
    PERFORM dq.log_check(p_run, 'DQ01',
        (SELECT count(*) FROM raw.cbi_mortgage_arrears_open_data),
        (SELECT count(*) FROM raw.cbi_mortgage_arrears_open_data
          WHERE COALESCE(btrim(reporting_date), '') = '' OR COALESCE(btrim(entity_group), '') = ''
             OR COALESCE(btrim(format_code), '') = ''    OR COALESCE(btrim(category), '') = ''
             OR COALESCE(btrim(row_position), '') = ''   OR COALESCE(btrim(column_position), '') = ''
             OR COALESCE(btrim(row_label), '') = ''      OR COALESCE(btrim(observation_type), '') = ''),
        'Eight key columns tested per row');

    /* DQ02 Exactly one value column populated */
    PERFORM dq.log_check(p_run, 'DQ02',
        (SELECT count(*) FROM raw.cbi_mortgage_arrears_open_data),
        (SELECT count(*) FROM raw.cbi_mortgage_arrears_open_data WHERE (observation IS NULL) = (number_of_accounts IS NULL)),
        'Rows with both value columns filled, or neither');

    /* DQ03 Value present after cleaning */
    PERFORM dq.log_check(p_run, 'DQ03',
        (SELECT count(*) FROM clean.mortgage_observation WHERE dq_status <> 'quarantined'),
        (SELECT count(*) FROM clean.mortgage_observation WHERE dq_status <> 'quarantined' AND value IS NULL),
        'Non-quarantined clean rows with no numeric value');

    /* DQ04 Value cells are numeric text. Tested = populated value cells in both columns. */
    PERFORM dq.log_check(p_run, 'DQ04',
        (SELECT count(observation) + count(number_of_accounts) FROM raw.cbi_mortgage_arrears_open_data),
        (SELECT count(*) FILTER (WHERE observation IS NOT NULL AND regexp_replace(btrim(observation), ',', '', 'g') !~ '^[0-9]+$')
              + count(*) FILTER (WHERE number_of_accounts IS NOT NULL AND regexp_replace(btrim(number_of_accounts), ',', '', 'g') !~ '^[0-9]+$')
           FROM raw.cbi_mortgage_arrears_open_data),
        'Populated value cells that are not digits with optional commas and spaces');

    /* DQ05 Reporting date parses */
    PERFORM dq.log_check(p_run, 'DQ05',
        (SELECT count(*) FROM raw.cbi_mortgage_arrears_open_data),
        (SELECT count(*) FROM raw.cbi_mortgage_arrears_open_data WHERE clean.safe_to_date(reporting_date) IS NULL),
        'Rows whose reporting date is not a real dd/mm/yyyy date');

    /* DQ06 Reporting date is a calendar quarter end */
    PERFORM dq.log_check(p_run, 'DQ06',
        (SELECT count(*) FROM raw.cbi_mortgage_arrears_open_data WHERE clean.safe_to_date(reporting_date) IS NOT NULL),
        (SELECT count(*) FROM raw.cbi_mortgage_arrears_open_data
          WHERE clean.safe_to_date(reporting_date) IS NOT NULL
            AND clean.safe_to_date(reporting_date) <>
                (date_trunc('quarter', clean.safe_to_date(reporting_date)) + INTERVAL '3 months' - INTERVAL '1 day')::DATE),
        (SELECT count(DISTINCT reporting_date)::TEXT || ' distinct dates are not quarter ends'
           FROM raw.cbi_mortgage_arrears_open_data
          WHERE clean.safe_to_date(reporting_date) IS NOT NULL
            AND clean.safe_to_date(reporting_date) <>
                (date_trunc('quarter', clean.safe_to_date(reporting_date)) + INTERVAL '3 months' - INTERVAL '1 day')::DATE));

    /* DQ07 Known category values */
    PERFORM dq.log_check(p_run, 'DQ07',
        (SELECT count(*) FROM raw.cbi_mortgage_arrears_open_data),
        (SELECT count(*) FROM raw.cbi_mortgage_arrears_open_data
          WHERE btrim(entity_group) NOT IN ('Banks', 'Non-Banks')
             OR btrim(format_code) NOT IN ('PDH', 'BTL')
             OR btrim(observation_type) <> ALL (v_types)),
        'Unknown lender group, format or observation type');

    /* DQ08 No duplicate raw rows */
    PERFORM dq.log_check(p_run, 'DQ08',
        (SELECT count(*) FROM raw.cbi_mortgage_arrears_open_data),
        (SELECT (SELECT count(*) FROM raw.cbi_mortgage_arrears_open_data)
              - (SELECT count(*) FROM (SELECT DISTINCT reporting_date, entity_group, format_code, category, row_position,
                                              column_position, row_label, observation_type, observation, number_of_accounts
                                       FROM raw.cbi_mortgage_arrears_open_data) AS u)),
        'Rows identical to another row in every source column');

    /* DQ09 Grain unique in clean */
    PERFORM dq.log_check(p_run, 'DQ09',
        (SELECT count(*) FROM clean.mortgage_observation WHERE dq_status <> 'quarantined'),
        (SELECT count(*) - count(DISTINCT (quarter_end_date, lender_group, portfolio_code, category, row_position, column_position))
           FROM clean.mortgage_observation WHERE dq_status <> 'quarantined'),
        'Rows sharing a grain with another non-quarantined row');

    /* DQ10 Grain unique in the fact table */
    PERFORM dq.log_check(p_run, 'DQ10',
        (SELECT count(*) FROM mart.fact_mortgage_measure),
        (SELECT count(*) - count(DISTINCT (date_key, lender_group_key, portfolio_key, measure_key)) FROM mart.fact_mortgage_measure),
        'Fact rows sharing the same four keys');

    /* DQ11 Values not negative */
    PERFORM dq.log_check(p_run, 'DQ11',
        (SELECT count(*) FROM clean.mortgage_observation WHERE dq_status <> 'quarantined'),
        (SELECT count(*) FROM clean.mortgage_observation WHERE dq_status <> 'quarantined' AND value < 0),
        'Clean values below zero');

    /* DQ12 Arrears amount does not exceed balance */
    PERFORM dq.log_check(p_run, 'DQ12',
        (SELECT count(*) FROM dq.v_arrears_amount_vs_balance),
        (SELECT count(*) FROM dq.v_arrears_amount_vs_balance WHERE arrears_value > balance_value),
        'Line items where arrears amount is above balance');

    /* DQ13 Arrears total does not exceed total outstanding */
    PERFORM dq.log_check(p_run, 'DQ13',
        (SELECT count(*) FROM dq.v_arrears_vs_outstanding),
        (SELECT count(*) FROM dq.v_arrears_vs_outstanding WHERE arrears_total > outstanding_total),
        'Segment quarters where arrears total is above total outstanding (accounts and balance)');

    /* DQ14 Arrears total equals sum of buckets, accounts, exact */
    PERFORM dq.log_check(p_run, 'DQ14',
        (SELECT count(*) FROM dq.v_arrears_total_vs_buckets WHERE metric_column = 1),
        (SELECT count(*) FROM dq.v_arrears_total_vs_buckets WHERE metric_column = 1 AND difference <> 0),
        'Segment quarters where account counts do not add up exactly');

    /* DQ15 Arrears total equals sum of buckets, euro, rounding tolerance of (n + 1) / 2 thousand */
    PERFORM dq.log_check(p_run, 'DQ15',
        (SELECT count(*) FROM dq.v_arrears_total_vs_buckets WHERE metric_column IN (2, 3)),
        (SELECT count(*) FROM dq.v_arrears_total_vs_buckets WHERE metric_column IN (2, 3) AND abs(difference) * 2 > n_leaf + 1),
        (SELECT 'Largest absolute gap observed: ' || COALESCE(max(abs(difference)), 0)::TEXT || ' thousand euro; '
                || count(*) FILTER (WHERE difference <> 0)::TEXT || ' comparisons differ by rounding'
           FROM dq.v_arrears_total_vs_buckets WHERE metric_column IN (2, 3)));

    /* DQ16 Legal status counts equal accounts in arrears */
    PERFORM dq.log_check(p_run, 'DQ16',
        (SELECT count(*) FROM dq.v_legal_status_vs_arrears_total),
        (SELECT count(*) FROM dq.v_legal_status_vs_arrears_total WHERE difference <> 0),
        'Segment quarters where the four legal status counts differ from total accounts in arrears');

    /* DQ17 Every clean measure exists in dim_measure */
    PERFORM dq.log_check(p_run, 'DQ17',
        (SELECT count(*) FROM clean.mortgage_observation WHERE dq_status <> 'quarantined'),
        (SELECT count(*) FROM clean.mortgage_observation AS c
          WHERE c.dq_status <> 'quarantined'
            AND NOT EXISTS (SELECT 1 FROM mart.dim_measure AS dm
                             WHERE dm.category = c.category AND dm.source_row_position = c.row_position
                               AND dm.source_column_position = c.column_position)),
        'Clean rows with no matching dim_measure row');

    /* DQ18 Every clean quarter exists in dim_date */
    PERFORM dq.log_check(p_run, 'DQ18',
        (SELECT count(*) FROM clean.mortgage_observation WHERE dq_status <> 'quarantined'),
        (SELECT count(*) FROM clean.mortgage_observation AS c
          WHERE c.dq_status <> 'quarantined'
            AND NOT EXISTS (SELECT 1 FROM mart.dim_date AS d WHERE d.quarter_end_date = c.quarter_end_date)),
        'Clean rows whose quarter end is missing from dim_date');

    /* DQ19 Every fact row joins to all four dimensions */
    PERFORM dq.log_check(p_run, 'DQ19',
        (SELECT count(*) FROM mart.fact_mortgage_measure),
        (SELECT count(*) FROM mart.fact_mortgage_measure AS f
           LEFT JOIN mart.dim_date AS d ON d.date_key = f.date_key
           LEFT JOIN mart.dim_lender_group AS lg ON lg.lender_group_key = f.lender_group_key
           LEFT JOIN mart.dim_portfolio AS p ON p.portfolio_key = f.portfolio_key
           LEFT JOIN mart.dim_measure AS dm ON dm.measure_key = f.measure_key
          WHERE d.date_key IS NULL OR lg.lender_group_key IS NULL OR p.portfolio_key IS NULL OR dm.measure_key IS NULL),
        'Fact rows with a missing dimension row');

    /* DQ20 Every fact row traces to a raw row */
    PERFORM dq.log_check(p_run, 'DQ20',
        (SELECT count(*) FROM mart.fact_mortgage_measure),
        (SELECT count(*) FROM mart.fact_mortgage_measure AS f
          WHERE NOT EXISTS (SELECT 1 FROM raw.cbi_mortgage_arrears_open_data AS r WHERE r.raw_row_id = f.source_raw_row_id)),
        'Fact rows whose source_raw_row_id is not in raw');

    /* DQ21 Core measures present for every segment and quarter */
    PERFORM dq.log_check(p_run, 'DQ21',
        (SELECT count(*) FROM dq.v_core_measure_coverage),
        (SELECT count(*) FROM dq.v_core_measure_coverage WHERE NOT is_present),
        (SELECT COALESCE(string_agg(DISTINCT d.quarter_label || ' ' || lg.lender_group_name || ' ' || p.portfolio_code, '; '), 'none')
           FROM dq.v_core_measure_coverage AS v
           JOIN mart.dim_date AS d USING (date_key)
           JOIN mart.dim_lender_group AS lg USING (lender_group_key)
           JOIN mart.dim_portfolio AS p USING (portfolio_key)
          WHERE NOT v.is_present));

    /* DQ22 Every calendar quarter has data */
    PERFORM dq.log_check(p_run, 'DQ22',
        (SELECT count(*) FROM mart.dim_date),
        (SELECT count(*) FROM mart.dim_date AS d
          WHERE NOT EXISTS (SELECT 1 FROM mart.fact_mortgage_measure AS f WHERE f.date_key = d.date_key)),
        'Quarters in dim_date with no fact rows');

    /* DQ23 Possession continuity, observation only */
    PERFORM dq.log_check(p_run, 'DQ23',
        (SELECT count(*) FROM dq.v_possession_continuity),
        (SELECT count(*) FROM dq.v_possession_continuity WHERE start_of_quarter <> prior_quarter_end),
        'Segment quarters where start of quarter differs from the prior quarter end');
END;
$$;
