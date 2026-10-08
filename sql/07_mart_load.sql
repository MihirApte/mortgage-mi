/*
  07_mart_load.sql
  Purpose : Fill mart.dim_measure and mart.fact_mortgage_measure from the clean layer.

  Only clean rows with dq_status valid or corrected are loaded. Quarantined rows stay in
  clean with their reason, so nothing disappears without a record.

  dim_measure is derived from the data: one row for each distinct combination of category,
  row position and column position that appears in clean. The labels are tidied for display
  and the source wording is kept alongside in source_row_label.

  Euro signs are produced with chr(8364) so these scripts contain only plain ASCII. This
  matters on Windows, where psql may read a script in a code page that mangles other characters.
*/

TRUNCATE TABLE mart.fact_mortgage_measure;
DELETE FROM mart.dim_measure;
ALTER TABLE mart.dim_measure ALTER COLUMN measure_key RESTART WITH 1;

INSERT INTO mart.dim_measure (category, source_row_position, source_column_position,
                              line_item, source_row_label, metric_name, unit,
                              is_total, harmonised_bucket, harmonised_bucket_sort)
SELECT  m.category,
        m.row_position,
        m.column_position,
        upper(left(m.line_item_raw, 1)) || substr(m.line_item_raw, 2) AS line_item,
        m.row_label,
        CASE
            WHEN m.observation_type LIKE '%' || chr(8364) || '%' AND m.observation_type LIKE 'Balance%' THEN 'Outstanding balance'
            WHEN m.observation_type LIKE '%' || chr(8364) || '%'                                       THEN 'Arrears amount'
            WHEN m.observation_type = 'Number' AND m.category = 'Repossessions'                        THEN 'Properties'
            WHEN m.observation_type = 'Number'                                                         THEN 'Accounts'
            WHEN m.observation_type = 'Number, In Arrears, Restruc.'                                   THEN 'Accounts in arrears, restructured'
            WHEN m.observation_type = 'Number, Not Restruc., Co-operating'                             THEN 'Accounts not restructured, co-operating'
            WHEN m.observation_type = 'Not Co-operating, Legal Proceed. Initiate'                      THEN 'Accounts not co-operating, legal proceedings initiated'
            WHEN m.observation_type = 'Not Co-operating, Legal Proceed. Not Initiate'                  THEN 'Accounts not co-operating, legal proceedings not initiated'
            ELSE m.observation_type
        END AS metric_name,
        CASE
            WHEN m.observation_type LIKE '%' || chr(8364) || '%' THEN 'EUR thousands'
            WHEN m.category = 'Repossessions'                    THEN 'properties'
            ELSE 'accounts'
        END AS unit,
        (m.category = 'Arrears' AND m.row_position = 2) AS is_total,
        CASE
            WHEN m.category <> 'Arrears'  THEN NULL
            WHEN m.row_position = 3       THEN 'Up to 90 days'
            WHEN m.row_position = 4       THEN '91 to 180 days'
            WHEN m.row_position BETWEEN 5 AND 11 THEN 'Over 180 days'
        END AS harmonised_bucket,
        CASE
            WHEN m.category <> 'Arrears'  THEN NULL
            WHEN m.row_position = 3       THEN 1
            WHEN m.row_position = 4       THEN 2
            WHEN m.row_position BETWEEN 5 AND 11 THEN 3
        END AS harmonised_bucket_sort
FROM (
    SELECT DISTINCT
           c.category,
           c.row_position,
           c.column_position,
           c.row_label,
           c.observation_type,
           CASE c.category
               WHEN 'Arrears' THEN
                   CASE WHEN c.row_label = 'Arrears: Total mortgage accounts in arrears' THEN 'total in arrears'
                        ELSE regexp_replace(c.row_label, '^Arrears: Total mortgage accounts in arrears - ', '') END
               WHEN 'Total Outstanding' THEN 'total accounts outstanding'
               WHEN 'Repossessions' THEN regexp_replace(c.row_label, '^Repossessions: ', '')
               WHEN 'Restructures - By Type' THEN regexp_replace(c.row_label, '^Restructured Mortgages: ', '')
               WHEN 'Restructures - Overview' THEN regexp_replace(c.row_label, '^Restructured Mortgages: ', '')
               ELSE c.row_label
           END AS line_item_raw
    FROM clean.mortgage_observation AS c
    WHERE c.dq_status IN ('valid', 'corrected')
) AS m
ORDER BY m.category, m.row_position, m.column_position;

/* Stable codes for the five headline measures. DAX filters on these codes, not on label text,
   so a relabelled line item cannot silently change a KPI. */
UPDATE mart.dim_measure SET measure_code = CASE
    WHEN category = 'Arrears' AND source_row_position = 2 AND source_column_position = 1 THEN 'ARREARS_ACCOUNTS'
    WHEN category = 'Arrears' AND source_row_position = 2 AND source_column_position = 2 THEN 'ARREARS_BALANCE'
    WHEN category = 'Arrears' AND source_row_position = 2 AND source_column_position = 3 THEN 'ARREARS_AMOUNT'
    WHEN category = 'Total Outstanding' AND source_column_position = 1 THEN 'OUTSTANDING_ACCOUNTS'
    WHEN category = 'Total Outstanding' AND source_column_position = 2 THEN 'OUTSTANDING_BALANCE'
END
WHERE (category = 'Arrears' AND source_row_position = 2) OR category = 'Total Outstanding';

INSERT INTO mart.fact_mortgage_measure (date_key, lender_group_key, portfolio_key, measure_key, value, source_raw_row_id)
SELECT  d.date_key,
        lg.lender_group_key,
        p.portfolio_key,
        dm.measure_key,
        c.value,
        c.raw_row_id
FROM clean.mortgage_observation AS c
JOIN mart.dim_date          AS d  ON d.quarter_end_date  = c.quarter_end_date
JOIN mart.dim_lender_group  AS lg ON lg.lender_group_name = c.lender_group
JOIN mart.dim_portfolio     AS p  ON p.portfolio_code     = c.portfolio_code
JOIN mart.dim_measure       AS dm ON dm.category = c.category
                                 AND dm.source_row_position = c.row_position
                                 AND dm.source_column_position = c.column_position
WHERE c.dq_status IN ('valid', 'corrected');

ANALYZE mart.fact_mortgage_measure;
