/*
  run_day2.sql
  Master script for Day 2. Run from the repository root after Day 1:

      psql -X -v ON_ERROR_STOP=1 -U postgres -d mortgage_mi -f sql/run_day2.sql

  Order matters: clean, then mart, then the quality framework, then the run, then the
  independent controls, then the self-test.
*/

\pset pager off


\echo Day 2 : building clean layer
\i sql/06_clean_build.sql
\echo Day 2 : loading mart
\i sql/07_mart_load.sql
\echo Day 2 : creating data quality framework
\i sql/08_dq_ddl.sql
\i sql/09_dq_checks.sql
\echo Day 2 : running checks, reconciliation and issue tracker
\i sql/10_dq_run.sql
\echo Day 2 : independent control totals
\i sql/12_day2_controls.sql
\echo Day 2 : self-test of the checks
\i sql/11_dq_selftest.sql
\echo Day 2 : quarantine path test
\i sql/13_clean_quarantine_test.sql
