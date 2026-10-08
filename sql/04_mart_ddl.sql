/*
  04_mart_ddl.sql
  Purpose : Star schema for Power BI. One fact table and four dimensions.

  GRAIN of mart.fact_mortgage_measure (the most important design statement):
    One row = one reported number for one quarter, one lender group (Banks or Non-Banks),
    one portfolio (PDH or BTL) and one measure (a line item with a metric, for example
    "Arrears, 91 to 180 days, number of accounts").

  Why a single long fact table with a measure dimension, not a wide table:
    The source publishes 133 different line item and metric combinations that change over
    time (new buckets were added in 2012 and 2019). A wide table would need a column per
    combination and would change shape whenever the Central Bank changes its report. A long
    fact plus dim_measure absorbs new line items by adding a dimension row, not a column.
    The cost is that DAX measures must filter dim_measure, which Day 3 covers.

  Keys: surrogate integer keys on every dimension, a composite primary key on the fact that
  enforces the grain, and foreign keys so orphan rows are impossible by construction.
  The fact also carries source_raw_row_id, a lineage pointer to raw.cbi_mortgage_arrears_open_data.

  Population: dim_date, dim_lender_group and dim_portfolio are filled here because they are
  small reference sets. dim_measure and the fact are filled from the clean layer on Day 2.
*/

/* CASCADE also drops the dq views built on these tables (Day 2). They are recreated by sql/09_dq_checks.sql. */
DROP TABLE IF EXISTS mart.fact_mortgage_measure CASCADE;
DROP TABLE IF EXISTS mart.dim_measure CASCADE;
DROP TABLE IF EXISTS mart.dim_portfolio CASCADE;
DROP TABLE IF EXISTS mart.dim_lender_group CASCADE;
DROP TABLE IF EXISTS mart.dim_date CASCADE;

/* Section: dim_date : one row per calendar quarter end */
CREATE TABLE mart.dim_date (
    date_key              INTEGER  PRIMARY KEY,         /* yyyymmdd of the quarter end, e.g. 20251231 */
    quarter_end_date      DATE     NOT NULL UNIQUE,
    calendar_year         SMALLINT NOT NULL,
    calendar_quarter      SMALLINT NOT NULL CHECK (calendar_quarter BETWEEN 1 AND 4),
    quarter_label         TEXT     NOT NULL,            /* e.g. 2025 Q4 */
    quarter_sort          INTEGER  NOT NULL UNIQUE,     /* year * 10 + quarter, sorts the label correctly */
    prior_quarter_key     INTEGER  REFERENCES mart.dim_date (date_key)  /* NULL for the first quarter */
);

/* Quarter ends are generated from calendar rules, not taken from the file, because the
   source reporting dates are working-day adjusted (for example 30/12/2016 for Q4 2016)
   and two are malformed (01/09/2025, 01/12/2025). The clean layer maps each source date to
   its calendar quarter end. The range matches the first and last quarter in the source. */
INSERT INTO mart.dim_date (date_key, quarter_end_date, calendar_year, calendar_quarter,
                           quarter_label, quarter_sort)
SELECT  to_char(q_end, 'YYYYMMDD')::INTEGER,
        q_end,
        EXTRACT(YEAR    FROM q_end)::SMALLINT,
        EXTRACT(QUARTER FROM q_end)::SMALLINT,
        EXTRACT(YEAR FROM q_end)::INTEGER || ' Q' || EXTRACT(QUARTER FROM q_end)::INTEGER,
        EXTRACT(YEAR FROM q_end)::INTEGER * 10 + EXTRACT(QUARTER FROM q_end)::INTEGER
FROM (
    SELECT (date_trunc('quarter', d) + INTERVAL '3 months' - INTERVAL '1 day')::DATE AS q_end
    FROM generate_series(DATE '2009-07-01', DATE '2026-01-01', INTERVAL '3 months') AS g(d)
) AS quarters
ORDER BY q_end;

UPDATE mart.dim_date AS cur
SET    prior_quarter_key = prev.date_key
FROM   mart.dim_date AS prev
WHERE  prev.quarter_sort = CASE WHEN cur.calendar_quarter = 1
                                THEN (cur.calendar_year - 1) * 10 + 4
                                ELSE cur.calendar_year * 10 + cur.calendar_quarter - 1 END;

/* Section: dim_lender_group */
CREATE TABLE mart.dim_lender_group (
    lender_group_key   SMALLINT PRIMARY KEY,
    lender_group_name  TEXT NOT NULL UNIQUE,
    description        TEXT NOT NULL
);

INSERT INTO mart.dim_lender_group (lender_group_key, lender_group_name, description) VALUES
    (1, 'Banks',     'Regulated retail banks reporting to the Central Bank of Ireland'),
    (2, 'Non-Banks', 'Non-bank lenders and loan owners reporting to the Central Bank of Ireland');

/* Section: dim_portfolio */
CREATE TABLE mart.dim_portfolio (
    portfolio_key   SMALLINT PRIMARY KEY,
    portfolio_code  TEXT NOT NULL UNIQUE,     /* value of the source Format column */
    portfolio_name  TEXT NOT NULL
);

INSERT INTO mart.dim_portfolio (portfolio_key, portfolio_code, portfolio_name) VALUES
    (1, 'PDH', 'Principal dwelling house (owner occupied)'),
    (2, 'BTL', 'Buy-to-let');

/* Section: dim_measure : what is being measured */
CREATE TABLE mart.dim_measure (
    measure_key              INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    category                 TEXT     NOT NULL,   /* source Category, e.g. Arrears */
    source_row_position      SMALLINT NOT NULL,
    source_column_position   SMALLINT NOT NULL,
    line_item                TEXT     NOT NULL,   /* cleaned label, e.g. 91 to 180 days */
    source_row_label         TEXT     NOT NULL,   /* label exactly as published */
    metric_name              TEXT     NOT NULL,   /* Accounts, Balance, Arrears amount, etc. */
    unit                     TEXT     NOT NULL CHECK (unit IN ('accounts', 'properties', 'EUR thousands')),
    is_total                 BOOLEAN  NOT NULL DEFAULT FALSE,  /* TRUE rows are sums of their components */
    harmonised_bucket        TEXT,                 /* arrears bucket comparable across all years */
    harmonised_bucket_sort   SMALLINT,
    measure_code             TEXT UNIQUE,          /* stable code for headline measures only, used by DAX, NULL otherwise */
    UNIQUE (category, source_row_position, source_column_position)
);

COMMENT ON COLUMN mart.dim_measure.is_total IS
  'Total rows equal the sum of their component rows. Never add a total and its components together.';
COMMENT ON COLUMN mart.dim_measure.harmonised_bucket IS
  'The source changed arrears buckets in 2012 and 2019. This maps every scheme to Up to 90 days, 91 to 180 days, Over 180 days so time series stay comparable.';

/* Section: fact table */
CREATE TABLE mart.fact_mortgage_measure (
    date_key            INTEGER  NOT NULL REFERENCES mart.dim_date (date_key),
    lender_group_key    SMALLINT NOT NULL REFERENCES mart.dim_lender_group (lender_group_key),
    portfolio_key       SMALLINT NOT NULL REFERENCES mart.dim_portfolio (portfolio_key),
    measure_key         INTEGER  NOT NULL REFERENCES mart.dim_measure (measure_key),
    value               BIGINT   NOT NULL CHECK (value >= 0),   /* counts or EUR thousands, see dim_measure.unit */
    source_raw_row_id   BIGINT   NOT NULL UNIQUE,                /* lineage pointer to raw.cbi_mortgage_arrears_open_data */
    PRIMARY KEY (date_key, lender_group_key, portfolio_key, measure_key)
);

/* The primary key already indexes the join path from date. Foreign key columns used for
   joins from other dimensions get their own indexes. */
CREATE INDEX ix_fact_lender_group ON mart.fact_mortgage_measure (lender_group_key);
CREATE INDEX ix_fact_portfolio    ON mart.fact_mortgage_measure (portfolio_key);
CREATE INDEX ix_fact_measure      ON mart.fact_mortgage_measure (measure_key);

COMMENT ON TABLE mart.fact_mortgage_measure IS
  'Grain: one row per quarter, lender group, portfolio and measure. Value unit is given by dim_measure.unit.';
