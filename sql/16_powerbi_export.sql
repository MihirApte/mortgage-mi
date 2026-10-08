/*
  16_powerbi_export.sql
  Purpose : Write the tables Power BI reads to CSV files in powerbi/data.

  Run from the repository root, because the file paths are relative to where psql is started.
  Files are UTF-8 with a header row. Booleans are written as true or false so Power BI types them
  correctly. Dates are ISO (yyyy-mm-dd), which Power BI reads without regional date confusion.
  Power BI could also connect straight to PostgreSQL. CSV files make the model easy to
  reproduce on any laptop without a database server.
*/

\copy (SELECT date_key, quarter_end_date, calendar_year, calendar_quarter, quarter_label, quarter_sort, prior_quarter_key, is_complete_quarter::text AS is_complete_quarter, is_latest_complete_quarter::text AS is_latest_complete_quarter FROM mart.v_bi_dim_date ORDER BY date_key) TO 'powerbi/data/dim_date.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

\copy (SELECT segment_key, lender_group_key, portfolio_key, lender_group_name, portfolio_code, portfolio_name, segment_label FROM mart.v_bi_dim_segment ORDER BY segment_key) TO 'powerbi/data/dim_segment.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

\copy (SELECT measure_key, category, source_row_position, source_column_position, line_item, source_row_label, metric_name, unit, is_total::text AS is_total, harmonised_bucket, harmonised_bucket_sort, measure_code FROM mart.dim_measure ORDER BY measure_key) TO 'powerbi/data/dim_measure.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

\copy (SELECT date_key, segment_key, measure_key, value, source_raw_row_id FROM mart.v_bi_fact ORDER BY date_key, segment_key, measure_key) TO 'powerbi/data/fact_mortgage_measure.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

\copy (SELECT rule_id, dimension, layer, rule_name, description, severity, on_failure FROM dq.rule ORDER BY rule_id) TO 'powerbi/data/dq_rule.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

\copy (SELECT check_id, run_label, rule_id, rows_tested, rows_failed, pct_failed, status, detail FROM dq.check_result ORDER BY rule_id) TO 'powerbi/data/dq_check_result.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

\copy (SELECT recon_id, check_name, breakdown, from_layer, from_value, to_layer, to_value, difference, status, note FROM dq.reconciliation ORDER BY recon_id) TO 'powerbi/data/dq_reconciliation.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

\copy (SELECT issue_id, found_in, rule_ref, issue, rows_affected, severity, resolution, status FROM dq.issue_log ORDER BY issue_id) TO 'powerbi/data/dq_issue_log.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

\copy (SELECT quarter_label, segment, kpi_code, kpi_value FROM dq.expected_kpi ORDER BY quarter_label, segment, kpi_code) TO 'powerbi/data/expected_kpi.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
