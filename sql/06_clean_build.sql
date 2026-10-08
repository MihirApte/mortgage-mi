/*
  06_clean_build.sql
  Purpose : Build the clean layer from the raw layer. One clean row per raw row.

  Principles
    1. Nothing is deleted. A row that cannot be trusted is kept and marked quarantined,
       so row counts always reconcile and every exclusion is visible.
    2. Every change is recorded in a flag column, so the tracker can count it.
    3. Raw is read only. Clean is rebuilt from scratch on every run, so it is repeatable.

  Rules implemented
    C1  Trim text and cast positions to integers.
    C2  Pick the value column by metric type. Euro metrics (Balance, Arrears) live in the
        Observation column. All other metrics are counts and live in Number of Accounts.
    C3  Strip thousands commas and padding spaces, then cast to bigint. A value that is not
        purely digits afterwards is left NULL and the row is quarantined.
    C4  If the other value column is also populated (70 rows in the 31 March 2026 return),
        ignore that stray value, keep the expected column and flag the row as corrected.
    C5  Map every reporting date to its calendar quarter end:
          as_published            already a quarter end
          working_day_adjusted    a weekday up to 3 days before quarter end (last working day)
          repaired_malformed_date explicit entries in clean.reporting_date_map_repairs below
          unmapped                anything else, which quarantines the row
    C6  If two clean rows share the same grain after mapping, keep the lowest raw_row_id and
        quarantine the others.
*/

/* A safe date parser: returns NULL instead of an error for impossible dates. */
CREATE OR REPLACE FUNCTION clean.safe_to_date(p_text TEXT)
RETURNS DATE
LANGUAGE plpgsql IMMUTABLE
AS $$
BEGIN
    IF p_text IS NULL OR p_text !~ '^[0-9]{2}/[0-9]{2}/[0-9]{4}$' THEN
        RETURN NULL;
    END IF;
    RETURN to_date(p_text, 'DD/MM/YYYY');
EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
END;
$$;

/* A safe number parser: strips commas and spaces, returns NULL unless the rest is all digits. */
CREATE OR REPLACE FUNCTION clean.safe_to_bigint(p_text TEXT)
RETURNS BIGINT
LANGUAGE sql IMMUTABLE
AS $$
    SELECT CASE WHEN regexp_replace(btrim(p_text), ',', '', 'g') ~ '^[0-9]{1,15}$'
                THEN regexp_replace(btrim(p_text), ',', '', 'g')::BIGINT
           END;
$$;

DROP TABLE IF EXISTS clean.mortgage_observation;
DROP TABLE IF EXISTS clean.reporting_date_map;
DROP TABLE IF EXISTS clean.reporting_date_map_repairs;

/* Explicit, evidenced repairs for the two malformed reporting dates. Kept as data, not buried
   in code, so a reviewer can see exactly what was assumed and why. */
CREATE TABLE clean.reporting_date_map_repairs (
    reporting_date_raw  TEXT PRIMARY KEY,
    quarter_end_date    DATE NOT NULL,
    evidence            TEXT NOT NULL
);

INSERT INTO clean.reporting_date_map_repairs (reporting_date_raw, quarter_end_date, evidence) VALUES
 ('01/09/2025', DATE '2025-09-30',
  'Holds only euro metrics (Balance, Arrears). Zero key overlap with the 30/09/2025 rows, which hold only count metrics. Together they make 376 rows, the same size as the 30/06/2025 return.'),
 ('01/12/2025', DATE '2025-12-31',
  'Holds a complete return (379 rows, all metric types). No other date exists for Q4 2025, and the size matches adjacent quarters. Inference, not confirmed by the publisher.');

/* One row per distinct reporting date text in raw, with the rule used. */
CREATE TABLE clean.reporting_date_map AS
WITH dates AS (
    SELECT reporting_date AS reporting_date_raw,
           clean.safe_to_date(reporting_date) AS d
    FROM raw.cbi_mortgage_arrears_open_data
    GROUP BY reporting_date
),
calc AS (
    SELECT reporting_date_raw,
           d,
           (date_trunc('quarter', d) + INTERVAL '3 months' - INTERVAL '1 day')::DATE AS calendar_quarter_end
    FROM dates
)
SELECT c.reporting_date_raw,
       CASE
           WHEN r.reporting_date_raw IS NOT NULL THEN r.quarter_end_date
           WHEN c.d IS NULL THEN NULL
           WHEN c.d = c.calendar_quarter_end THEN c.calendar_quarter_end
           WHEN c.calendar_quarter_end - c.d BETWEEN 1 AND 3 AND EXTRACT(ISODOW FROM c.d) <= 5 THEN c.calendar_quarter_end
       END AS quarter_end_date,
       CASE
           WHEN r.reporting_date_raw IS NOT NULL THEN 'repaired_malformed_date'
           WHEN c.d IS NULL THEN 'unmapped'
           WHEN c.d = c.calendar_quarter_end THEN 'as_published'
           WHEN c.calendar_quarter_end - c.d BETWEEN 1 AND 3 AND EXTRACT(ISODOW FROM c.d) <= 5 THEN 'working_day_adjusted'
           ELSE 'unmapped'
       END AS date_rule
FROM calc AS c
LEFT JOIN clean.reporting_date_map_repairs AS r USING (reporting_date_raw);

ALTER TABLE clean.reporting_date_map ADD PRIMARY KEY (reporting_date_raw);

/* Main clean table. Built in two passes: parse and flag first, then detect grain duplicates. */
CREATE TABLE clean.mortgage_observation AS
WITH parsed AS (
    SELECT  r.raw_row_id,
            m.quarter_end_date,
            COALESCE(m.date_rule, 'unmapped')                       AS date_rule,
            btrim(r.entity_group)                                   AS lender_group,
            btrim(r.format_code)                                    AS portfolio_code,
            btrim(r.category)                                       AS category,
            CASE WHEN btrim(r.row_position)    ~ '^[0-9]{1,3}$' THEN btrim(r.row_position)::SMALLINT    END AS row_position,
            CASE WHEN btrim(r.column_position) ~ '^[0-9]{1,3}$' THEN btrim(r.column_position)::SMALLINT END AS column_position,
            btrim(r.row_label)                                      AS row_label,
            btrim(r.observation_type)                               AS observation_type,
            /* C2: which source column should hold the value for this metric */
            CASE WHEN r.observation_type LIKE '%' || chr(8364) || '%' THEN 'observation'
                 ELSE 'number_of_accounts' END                      AS value_column,
            r.observation,
            r.number_of_accounts
    FROM raw.cbi_mortgage_arrears_open_data AS r
    LEFT JOIN clean.reporting_date_map AS m ON m.reporting_date_raw = r.reporting_date
),
valued AS (
    SELECT  p.*,
            CASE WHEN p.value_column = 'observation' THEN p.observation ELSE p.number_of_accounts END AS value_text,
            CASE WHEN p.value_column = 'observation' THEN p.number_of_accounts ELSE p.observation END AS other_text
    FROM parsed AS p
),
flagged AS (
    SELECT  v.raw_row_id,
            v.quarter_end_date,
            v.date_rule,
            v.lender_group,
            v.portfolio_code,
            v.category,
            v.row_position,
            v.column_position,
            v.row_label,
            v.observation_type,
            v.value_column,
            clean.safe_to_bigint(v.value_text)                      AS value,
            (v.value_text IS NOT NULL AND v.value_text ~ '[, ]')    AS number_text_cleaned,
            (v.other_text IS NOT NULL)                              AS stray_value_ignored,
            (v.date_rule IN ('working_day_adjusted', 'repaired_malformed_date')) AS date_remapped,
            v.other_text                                            AS stray_value_text
    FROM valued AS v
),
graded AS (
    SELECT  f.*,
            CASE
                WHEN f.quarter_end_date IS NULL                                  THEN 'date could not be mapped to a quarter end'
                WHEN f.lender_group NOT IN ('Banks', 'Non-Banks')                THEN 'unknown lender group'
                WHEN f.portfolio_code NOT IN ('PDH', 'BTL')                      THEN 'unknown portfolio code'
                WHEN f.row_position IS NULL OR f.column_position IS NULL         THEN 'position is not a number'
                WHEN f.value IS NULL                                             THEN 'value missing or not numeric'
            END AS quarantine_reason
    FROM flagged AS f
),
ranked AS (
    SELECT  g.*,
            row_number() OVER (
                PARTITION BY g.quarter_end_date, g.lender_group, g.portfolio_code, g.category, g.row_position, g.column_position
                ORDER BY g.raw_row_id
            ) AS grain_rank
    FROM graded AS g
    WHERE g.quarantine_reason IS NULL
)
SELECT  g.raw_row_id,
        g.quarter_end_date,
        g.date_rule,
        g.lender_group,
        g.portfolio_code,
        g.category,
        g.row_position,
        g.column_position,
        g.row_label,
        g.observation_type,
        g.value_column,
        g.value,
        g.number_text_cleaned,
        g.stray_value_ignored,
        g.date_remapped,
        g.stray_value_text,
        CASE
            WHEN COALESCE(g.quarantine_reason, CASE WHEN rk.grain_rank > 1 THEN 'duplicate of an earlier row at the same grain' END) IS NOT NULL
                 THEN 'quarantined'
            WHEN g.stray_value_ignored OR g.date_remapped THEN 'corrected'
            ELSE 'valid'
        END AS dq_status,
        COALESCE(g.quarantine_reason, CASE WHEN rk.grain_rank > 1 THEN 'duplicate of an earlier row at the same grain' END,
                 CASE WHEN g.stray_value_ignored AND g.date_remapped THEN 'stray value in other column ignored; reporting date remapped'
                      WHEN g.stray_value_ignored THEN 'stray value in other column ignored'
                      WHEN g.date_remapped THEN 'reporting date remapped to calendar quarter end' END) AS dq_reason
FROM graded AS g
LEFT JOIN ranked AS rk ON rk.raw_row_id = g.raw_row_id;

ALTER TABLE clean.mortgage_observation ADD PRIMARY KEY (raw_row_id);
ALTER TABLE clean.mortgage_observation ADD CONSTRAINT ck_clean_status CHECK (dq_status IN ('valid', 'corrected', 'quarantined'));
CREATE INDEX ix_clean_grain ON clean.mortgage_observation (quarter_end_date, lender_group, portfolio_code, category, row_position, column_position);

COMMENT ON TABLE clean.mortgage_observation IS
  'One row per raw row. dq_status valid or corrected rows flow to the mart. quarantined rows are kept here with dq_reason.';
