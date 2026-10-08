/*
  run_day1.sql
  Master script for Day 1. Run from the repository root:

      psql -X -v ON_ERROR_STOP=1 -U postgres -d mortgage_mi -f sql/run_day1.sql

  -X               ignore any personal psql settings so the run is reproducible
  ON_ERROR_STOP=1  stop at the first error instead of carrying on
*/

\pset pager off


\echo Day 1 : creating schemas
\i sql/01_schemas.sql
\echo Day 1 : creating raw table
\i sql/02_raw_ddl.sql
\echo Day 1 : loading raw data
\i sql/03_raw_load.sql
\echo Day 1 : creating star schema
\i sql/04_mart_ddl.sql
\echo Day 1 : running checks
\i sql/05_day1_checks.sql
