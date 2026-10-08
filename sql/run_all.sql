/*
  run_all.sql
  Rebuilds the whole pipeline from the raw file to the tested mart. Run from the repository root:

      psql -X -v ON_ERROR_STOP=1 -U postgres -d mortgage_mi -f sql/run_all.sql
*/

\pset pager off


\i sql/run_day1.sql
\i sql/run_day2.sql
\i sql/run_day3.sql

\echo
\echo ================================================================
\echo PIPELINE COMPLETE. You reached this line, so every check, control
\echo total, self-test and rollback test above passed. Any failure would
\echo have stopped the run with an ERROR before this point.
\echo ================================================================
