/*
  14_bi_views.sql
  Purpose : Reporting views that Power BI reads. The star schema tables stay exactly as built.

  Why views and not extra columns in the mart tables:
    The mart is the tested, reconciled layer. The BI layer is a thin presentation layer on top of it.
    Anything added here is derived from the mart, so it cannot drift away from it.

  What the views add:
    v_bi_dim_segment    A 4 row segment dimension (Banks BTL, Banks PDH, Non-Banks BTL, Non-Banks PDH).
                        The fact stores lender group and portfolio as two keys. A single segment key lets
                        Power BI rank segments with one simple RANKX over one column.
    v_bi_fact           The fact table plus segment_key. Same rows, same values.
    v_bi_dim_date       dim_date plus two flags computed from the data: is_complete_quarter is TRUE when all
                        4 segments report all 5 headline measures, and is_latest_complete_quarter marks
                        the newest such quarter. The dashboard defaults to that quarter, so it never shows
                        a headline total that silently leaves a segment out.
*/

DROP VIEW IF EXISTS mart.v_bi_fact;
DROP VIEW IF EXISTS mart.v_bi_dim_segment;
DROP VIEW IF EXISTS mart.v_bi_dim_date;

CREATE VIEW mart.v_bi_dim_segment AS
SELECT  (lg.lender_group_key * 10 + p.portfolio_key)::INTEGER AS segment_key,
        lg.lender_group_key,
        p.portfolio_key,
        lg.lender_group_name,
        p.portfolio_code,
        p.portfolio_name,
        lg.lender_group_name || ' ' || p.portfolio_code        AS segment_label
FROM mart.dim_lender_group AS lg
CROSS JOIN mart.dim_portfolio AS p;

CREATE VIEW mart.v_bi_fact AS
SELECT  f.date_key,
        (f.lender_group_key * 10 + f.portfolio_key)::INTEGER AS segment_key,
        f.measure_key,
        f.value,
        f.source_raw_row_id
FROM mart.fact_mortgage_measure AS f;

CREATE VIEW mart.v_bi_dim_date AS
WITH headline AS (
    SELECT  f.date_key,
            count(DISTINCT (f.lender_group_key, f.portfolio_key, m.measure_code)) AS n_values
    FROM mart.fact_mortgage_measure AS f
    JOIN mart.dim_measure AS m USING (measure_key)
    WHERE m.measure_code IS NOT NULL
    GROUP BY f.date_key
),
flagged AS (
    SELECT  d.*,
            COALESCE(h.n_values = 20, FALSE) AS is_complete_quarter    /* 4 segments x 5 headline measures */
    FROM mart.dim_date AS d
    LEFT JOIN headline AS h USING (date_key)
)
SELECT  fl.date_key,
        fl.quarter_end_date,
        fl.calendar_year,
        fl.calendar_quarter,
        fl.quarter_label,
        fl.quarter_sort,
        fl.prior_quarter_key,
        fl.is_complete_quarter,
        (fl.is_complete_quarter
         AND fl.quarter_end_date = (SELECT max(quarter_end_date) FROM flagged WHERE is_complete_quarter)) AS is_latest_complete_quarter
FROM flagged AS fl;

/* Section: the views must not change the numbers */
DO $$
DECLARE
    n_fact BIGINT; n_view BIGINT; s_fact NUMERIC; s_view NUMERIC; n_complete INTEGER; latest TEXT;
BEGIN
    SELECT count(*), sum(value) INTO n_fact, s_fact FROM mart.fact_mortgage_measure;
    SELECT count(*), sum(value) INTO n_view, s_view FROM mart.v_bi_fact;
    IF n_fact <> n_view OR s_fact <> s_view THEN
        RAISE EXCEPTION 'BI view check failed: fact % rows sum % vs view % rows sum %', n_fact, s_fact, n_view, s_view;
    END IF;
    IF (SELECT count(*) FROM mart.v_bi_fact f LEFT JOIN mart.v_bi_dim_segment s USING (segment_key) WHERE s.segment_key IS NULL) > 0 THEN
        RAISE EXCEPTION 'BI view check failed: a fact row has no segment';
    END IF;
    SELECT count(*) FILTER (WHERE is_complete_quarter) INTO n_complete FROM mart.v_bi_dim_date;
    SELECT quarter_label INTO latest FROM mart.v_bi_dim_date WHERE is_latest_complete_quarter;
    RAISE NOTICE 'BI views check passed: % fact rows and sum % unchanged, % complete quarters, latest complete quarter %',
                 n_view, s_view, n_complete, latest;
END $$;
