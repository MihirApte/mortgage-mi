/*
  01_schemas.sql
  Purpose : Create the four schemas that represent the pipeline layers.
  Layers  : raw   = exact copy of the source file, all text, never modified
            clean = typed, trimmed, standardised rows with data quality flags (built on Day 2)
            mart  = star schema used by Power BI
            dq    = data quality checks, issue tracker and reconciliation results (built on Day 2)
  Re-runnable: yes. Schemas are created only if missing.
*/

CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS clean;
CREATE SCHEMA IF NOT EXISTS mart;
CREATE SCHEMA IF NOT EXISTS dq;

COMMENT ON SCHEMA raw   IS 'Source data exactly as received. All columns text. Never updated.';
COMMENT ON SCHEMA clean IS 'Typed and standardised rows, one per raw row, with data quality flags.';
COMMENT ON SCHEMA mart  IS 'Star schema (one fact table, four dimensions) consumed by Power BI.';
COMMENT ON SCHEMA dq    IS 'Data quality rules, results, reconciliation and the issue tracker.';
