/*
  15_expected_kpis.sql
  Purpose : Compute the headline KPIs in plain SQL, as the answer key for testing Power BI.

  The DAX measures in powerbi/measures.dax are a second, separate implementation of the same
  definitions. On Day 4 the dashboard cards are compared with this table. If SQL and DAX
  agree, neither has a logic slip. If they disagree, one of them is wrong and the difference
  tells you which.

  Definitions (the same words are used in docs/04_power_bi_model_and_dax.md):
    arrears_rate_accounts   = accounts in arrears / total accounts outstanding
    arrears_rate_balance    = balance of accounts in arrears / total outstanding balance
    over_180_share_accounts = accounts in arrears for over 180 days / accounts in arrears
    qoq_change_*            = value this quarter minus value in the prior quarter

  Balances and account counts are positions at a quarter end. They can be added across
  segments in one quarter, but never across quarters. The segment "All segments" is the
  sum of the four segments, and only exists where all four segments are reported.
  Every number comes from mart tables. Nothing is typed in.
*/

DROP TABLE IF EXISTS dq.expected_kpi;

CREATE TABLE dq.expected_kpi (
    quarter_label TEXT    NOT NULL,
    segment       TEXT    NOT NULL,
    kpi_code      TEXT    NOT NULL,
    kpi_value     NUMERIC,            /* NULL when it cannot be computed, for example no prior quarter */
    PRIMARY KEY (quarter_label, segment, kpi_code)
);

CREATE TEMP TABLE kpi_base AS
SELECT  d.date_key,
        d.quarter_label,
        d.prior_quarter_key,
        lg.lender_group_name || ' ' || p.portfolio_code AS segment,
        sum(f.value) FILTER (WHERE m.measure_code = 'ARREARS_ACCOUNTS')     AS arrears_accounts,
        sum(f.value) FILTER (WHERE m.measure_code = 'OUTSTANDING_ACCOUNTS') AS outstanding_accounts,
        sum(f.value) FILTER (WHERE m.measure_code = 'ARREARS_BALANCE')      AS arrears_balance,
        sum(f.value) FILTER (WHERE m.measure_code = 'OUTSTANDING_BALANCE')  AS outstanding_balance,
        sum(f.value) FILTER (WHERE m.measure_code = 'ARREARS_AMOUNT')       AS arrears_amount,
        sum(f.value) FILTER (WHERE m.harmonised_bucket = 'Over 180 days' AND m.metric_name = 'Accounts') AS over_180_accounts,
        sum(f.value) FILTER (WHERE m.harmonised_bucket = 'Up to 90 days' AND m.metric_name = 'Accounts') AS up_to_90_accounts,
        sum(f.value) FILTER (WHERE m.harmonised_bucket = '91 to 180 days' AND m.metric_name = 'Accounts') AS d91_to_180_accounts
FROM mart.fact_mortgage_measure AS f
JOIN mart.dim_measure      AS m  USING (measure_key)
JOIN mart.dim_date         AS d  USING (date_key)
JOIN mart.dim_lender_group AS lg USING (lender_group_key)
JOIN mart.dim_portfolio    AS p  USING (portfolio_key)
GROUP BY d.date_key, d.quarter_label, d.prior_quarter_key, lg.lender_group_name, p.portfolio_code;

/* Section: All segments, only for quarters where every one of the 4 segments has the 5 headline values */
INSERT INTO kpi_base
SELECT  date_key, quarter_label, prior_quarter_key, 'All segments',
        sum(arrears_accounts), sum(outstanding_accounts), sum(arrears_balance),
        sum(outstanding_balance), sum(arrears_amount), sum(over_180_accounts),
        sum(up_to_90_accounts), sum(d91_to_180_accounts)
FROM kpi_base
GROUP BY date_key, quarter_label, prior_quarter_key
HAVING count(*) = 4
   AND count(arrears_accounts) = 4 AND count(outstanding_accounts) = 4
   AND count(arrears_balance) = 4  AND count(outstanding_balance) = 4
   AND count(arrears_amount) = 4   AND count(over_180_accounts) = 4
   AND count(up_to_90_accounts) = 4 AND count(d91_to_180_accounts) = 4;

CREATE TEMP TABLE kpi_wide AS
SELECT  b.quarter_label, b.segment,
        b.arrears_accounts, b.outstanding_accounts, b.arrears_balance, b.outstanding_balance,
        b.arrears_amount, b.over_180_accounts, b.up_to_90_accounts, b.d91_to_180_accounts,
        b.arrears_accounts::NUMERIC / NULLIF(b.outstanding_accounts, 0)  AS arrears_rate_accounts,
        b.arrears_balance::NUMERIC  / NULLIF(b.outstanding_balance, 0)   AS arrears_rate_balance,
        b.over_180_accounts::NUMERIC / NULLIF(b.arrears_accounts, 0)     AS over_180_share_accounts,
        b.arrears_accounts - pr.arrears_accounts                         AS qoq_change_arrears_accounts,
        b.outstanding_balance - pr.outstanding_balance                   AS qoq_change_outstanding_balance,
        (b.arrears_accounts::NUMERIC / NULLIF(b.outstanding_accounts, 0))
          - (pr.arrears_accounts::NUMERIC / NULLIF(pr.outstanding_accounts, 0)) AS qoq_change_arrears_rate_accounts
FROM kpi_base AS b
LEFT JOIN kpi_base AS pr
       ON pr.date_key = b.prior_quarter_key AND pr.segment = b.segment;

INSERT INTO dq.expected_kpi (quarter_label, segment, kpi_code, kpi_value)
SELECT  w.quarter_label, w.segment, k.kpi_code, k.kpi_value
FROM kpi_wide AS w
CROSS JOIN LATERAL (VALUES
    ('arrears_accounts',                 w.arrears_accounts::NUMERIC),
    ('outstanding_accounts',             w.outstanding_accounts::NUMERIC),
    ('arrears_balance',                  w.arrears_balance::NUMERIC),
    ('outstanding_balance',              w.outstanding_balance::NUMERIC),
    ('arrears_amount',                   w.arrears_amount::NUMERIC),
    ('over_180_accounts',                w.over_180_accounts::NUMERIC),
    ('up_to_90_accounts',                w.up_to_90_accounts::NUMERIC),
    ('d91_to_180_accounts',              w.d91_to_180_accounts::NUMERIC),
    ('arrears_rate_accounts',            w.arrears_rate_accounts),
    ('arrears_rate_balance',             w.arrears_rate_balance),
    ('over_180_share_accounts',          w.over_180_share_accounts),
    ('qoq_change_arrears_accounts',      w.qoq_change_arrears_accounts::NUMERIC),
    ('qoq_change_outstanding_balance',   w.qoq_change_outstanding_balance::NUMERIC),
    ('qoq_change_arrears_rate_accounts', w.qoq_change_arrears_rate_accounts)
) AS k (kpi_code, kpi_value);

COMMENT ON TABLE dq.expected_kpi IS
  'Answer key for Power BI testing. Computed in SQL, independent of the DAX measures.';

/* Section: the three buckets must add to the total in arrears in every quarter and segment.
   The DAX bucket measure relies on this, so it is proved here, not assumed. */
DO $$
DECLARE
    n_bad INTEGER;
    n_all INTEGER;
BEGIN
    SELECT count(*) FILTER (WHERE up_to_90_accounts + d91_to_180_accounts + over_180_accounts <> arrears_accounts), count(*)
      INTO n_bad, n_all FROM kpi_wide WHERE up_to_90_accounts IS NOT NULL;
    IF n_bad > 0 THEN
        RAISE EXCEPTION 'Bucket check failed: % of % segment-quarters have buckets that do not add to the total', n_bad, n_all;
    END IF;
    RAISE NOTICE 'Bucket check passed: 3 harmonised buckets add exactly to total in arrears in all % segment-quarters', n_all;
END $$;

/* Section: the same check the dashboard will face: 4 segments sum to All segments for 2025 Q4 */
DO $$
DECLARE
    v_all NUMERIC;
    v_sum NUMERIC;
BEGIN
    SELECT kpi_value INTO v_all FROM dq.expected_kpi
     WHERE quarter_label = '2025 Q4' AND segment = 'All segments' AND kpi_code = 'arrears_accounts';
    SELECT sum(kpi_value) INTO v_sum FROM dq.expected_kpi
     WHERE quarter_label = '2025 Q4' AND segment <> 'All segments' AND kpi_code = 'arrears_accounts';
    IF v_all IS DISTINCT FROM v_sum OR v_all IS NULL THEN
        RAISE EXCEPTION 'Expected KPI check failed: All segments % vs sum of segments %', v_all, v_sum;
    END IF;
    RAISE NOTICE 'Expected KPI check passed: 2025 Q4 arrears accounts, 4 segments add to All segments (%)', v_all;
END $$;
