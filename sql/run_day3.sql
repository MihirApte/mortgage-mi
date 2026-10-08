/*
  run_day3.sql
  Master script for Day 3. Run from the repository root after Day 2:

      psql -X -v ON_ERROR_STOP=1 -U postgres -d mortgage_mi -f sql/run_day3.sql
*/

\pset pager off

\echo Day 3 : creating reporting views for Power BI
\i sql/14_bi_views.sql
\echo Day 3 : computing the SQL answer key for the KPIs
\i sql/15_expected_kpis.sql
\echo Day 3 : exporting CSV files for Power BI
\i sql/16_powerbi_export.sql
