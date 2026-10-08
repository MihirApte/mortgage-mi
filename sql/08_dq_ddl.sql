/*
  08_dq_ddl.sql
  Purpose : Tables that hold the data quality framework, so results can be queried, trended
            and shown on the dashboard, instead of living only in a console log.

    dq.rule            the catalogue of rules: what is tested, in which layer, how serious a failure is
    dq.check_result    one row per rule per run: rows tested, rows failed, status
    dq.reconciliation  layer-to-layer row counts and control totals
    dq.issue_log       the issue tracker: issue, rule, count, resolution

  Severity levels
    error    a failure means the pipeline output cannot be trusted, so the run stops
    warning  a known and explained condition. The run continues and the issue is logged
    info     an observation recorded for transparency, no action required
*/

DROP TABLE IF EXISTS dq.issue_log;
DROP TABLE IF EXISTS dq.reconciliation;
DROP TABLE IF EXISTS dq.check_result;
DROP TABLE IF EXISTS dq.rule;

CREATE TABLE dq.rule (
    rule_id      TEXT PRIMARY KEY,
    dimension    TEXT NOT NULL CHECK (dimension IN ('Completeness', 'Validity', 'Uniqueness', 'Reasonableness',
                                                    'Consistency', 'Referential integrity', 'Coverage', 'Continuity')),
    layer        TEXT NOT NULL CHECK (layer IN ('raw', 'clean', 'mart')),
    rule_name    TEXT NOT NULL,
    description  TEXT NOT NULL,
    severity     TEXT NOT NULL CHECK (severity IN ('error', 'warning', 'info')),
    on_failure   TEXT NOT NULL
);

CREATE TABLE dq.check_result (
    check_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    run_label    TEXT        NOT NULL,
    rule_id      TEXT        NOT NULL REFERENCES dq.rule (rule_id),
    rows_tested  BIGINT      NOT NULL CHECK (rows_tested >= 0),
    rows_failed  BIGINT      NOT NULL CHECK (rows_failed >= 0),
    pct_failed   NUMERIC(8, 3) NOT NULL,
    status       TEXT        NOT NULL CHECK (status IN ('pass', 'fail', 'warn', 'info')),
    detail       TEXT,
    checked_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE dq.reconciliation (
    recon_id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    check_name       TEXT   NOT NULL,
    breakdown        TEXT,
    from_layer       TEXT   NOT NULL,
    from_value       NUMERIC NOT NULL,
    to_layer         TEXT   NOT NULL,
    to_value         NUMERIC NOT NULL,
    difference       NUMERIC NOT NULL,
    status           TEXT   NOT NULL CHECK (status IN ('match', 'mismatch')),
    note             TEXT
);

CREATE TABLE dq.issue_log (
    issue_id       TEXT PRIMARY KEY,
    found_in       TEXT   NOT NULL,
    rule_ref       TEXT   NOT NULL,
    issue          TEXT   NOT NULL,
    rows_affected  BIGINT NOT NULL,
    severity       TEXT   NOT NULL CHECK (severity IN ('error', 'warning', 'info')),
    resolution     TEXT   NOT NULL,
    status         TEXT   NOT NULL CHECK (status IN ('resolved', 'accepted', 'monitor'))
);

INSERT INTO dq.rule (rule_id, dimension, layer, rule_name, description, severity, on_failure) VALUES
 ('DQ01', 'Completeness',         'raw',   'Key fields present',
  'Reporting date, lender group, format, category, row and column position, row label and observation type are all non-blank.',
  'error', 'Stop. A row without its keys cannot be placed in the model.'),
 ('DQ02', 'Completeness',         'raw',   'Exactly one value column populated',
  'Each row holds its value in either Observation or Number of Accounts. Neither or both is a failure.',
  'warning', 'Clean rule C4 keeps the expected column and ignores the stray one. Rows are flagged corrected.'),
 ('DQ03', 'Completeness',         'clean', 'Value present after cleaning',
  'Every clean row that is not quarantined has a numeric value.',
  'error', 'Stop. The parsing rules missed a case.'),
 ('DQ04', 'Validity',             'raw',   'Value cells are numeric text',
  'Every populated value cell is digits with optional thousands commas and padding spaces and nothing else.',
  'error', 'Stop. A new text pattern needs a cleaning rule.'),
 ('DQ05', 'Validity',             'raw',   'Reporting date parses',
  'Reporting date is a real date in dd/mm/yyyy format.',
  'error', 'Stop. Row would be quarantined.'),
 ('DQ06', 'Validity',             'raw',   'Reporting date is a calendar quarter end',
  'The return is quarterly, so the reporting date should be 31 March, 30 June, 30 September or 31 December.',
  'warning', 'Clean rule C5 maps working-day dates and two repaired malformed dates to the quarter end.'),
 ('DQ07', 'Validity',             'raw',   'Known category values',
  'Lender group is Banks or Non-Banks, format is PDH or BTL, observation type is one of the seven known types.',
  'error', 'Stop. A new value needs a dimension decision before loading.'),
 ('DQ08', 'Uniqueness',           'raw',   'No duplicate raw rows',
  'No two raw rows are identical in every source column.',
  'error', 'Stop. Investigate a double load or a duplicated extract.'),
 ('DQ09', 'Uniqueness',           'clean', 'Grain is unique in clean',
  'No two non-quarantined clean rows share quarter, lender group, portfolio, category, row position and column position.',
  'error', 'Stop. Clean rule C6 should have quarantined the extra row.'),
 ('DQ10', 'Uniqueness',           'mart',  'Grain is unique in the fact table',
  'No two fact rows share the same four dimension keys. The primary key also enforces this.',
  'error', 'Stop.'),
 ('DQ11', 'Reasonableness',       'clean', 'Values are not negative',
  'Counts and euro amounts cannot be below zero.',
  'error', 'Stop. The fact table also rejects negative values with a check constraint.'),
 ('DQ12', 'Reasonableness',       'mart',  'Arrears amount does not exceed balance',
  'For every line item, the arrears amount is at most the outstanding balance of the same accounts.',
  'error', 'Stop.'),
 ('DQ13', 'Reasonableness',       'mart',  'Arrears total does not exceed total outstanding',
  'Accounts in arrears cannot exceed accounts outstanding, and the balance of accounts in arrears cannot exceed total balance, for the same quarter and segment.',
  'error', 'Stop.'),
 ('DQ14', 'Consistency',          'mart',  'Arrears total equals sum of buckets (accounts)',
  'The count of accounts in arrears equals the sum of the arrears buckets. Counts must match exactly.',
  'error', 'Stop. Double counting or a missing bucket.'),
 ('DQ15', 'Consistency',          'mart',  'Arrears total equals sum of buckets (euro amounts)',
  'Euro amounts are published rounded to thousands, so each figure can be out by 0.5. The allowed gap is (number of buckets + 1) / 2 thousand euro.',
  'error', 'Stop.'),
 ('DQ16', 'Consistency',          'mart',  'Legal status counts equal accounts in arrears',
  'The four legal status categories should add up to the total accounts in arrears.',
  'warning', 'Source inconsistency. Values are kept as published and the quarter is logged in the tracker.'),
 ('DQ17', 'Referential integrity','clean', 'Every clean measure exists in dim_measure',
  'The combination of category, row position and column position in clean maps to a dim_measure row.',
  'error', 'Stop. dim_measure is missing a measure.'),
 ('DQ18', 'Referential integrity','clean', 'Every clean quarter exists in dim_date',
  'Each mapped quarter end exists in the date dimension.',
  'error', 'Stop. dim_date does not cover the data range.'),
 ('DQ19', 'Referential integrity','mart',  'Every fact row joins to all four dimensions',
  'No fact row is orphaned from dim_date, dim_lender_group, dim_portfolio or dim_measure. Foreign keys also enforce this.',
  'error', 'Stop.'),
 ('DQ20', 'Referential integrity','mart',  'Every fact row traces to a raw row',
  'source_raw_row_id exists in the raw table, so every number can be traced to the source file.',
  'error', 'Stop. Lineage is broken.'),
 ('DQ21', 'Coverage',             'mart',  'Core measures present for every segment and quarter',
  'Each lender group, portfolio and quarter in the fact table has the five core measures: arrears total (accounts, balance, arrears amount) and total outstanding (accounts, balance).',
  'warning', 'Not imputed. KPIs that need a missing measure show blank for that segment and quarter. Logged in the tracker.'),
 ('DQ22', 'Coverage',             'mart',  'Every calendar quarter has data',
  'Every quarter in dim_date between the first and last reporting quarter has fact rows.',
  'warning', 'Investigate a missing return or a date mapping problem.'),
 ('DQ23', 'Continuity',           'mart',  'Possessions at start equal prior quarter end',
  'Residential properties in possession at the beginning of a quarter should equal the end of the previous quarter. Observation only.',
  'info', 'No action. Recorded because the published figures do not always reconcile, possibly due to restatements.');

/* Helper used by the check procedure: works out status from severity and logs one result. */
CREATE OR REPLACE FUNCTION dq.log_check(p_run TEXT, p_rule TEXT, p_tested BIGINT, p_failed BIGINT, p_detail TEXT DEFAULT NULL)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_sev TEXT;
    v_status TEXT;
BEGIN
    SELECT severity INTO v_sev FROM dq.rule WHERE rule_id = p_rule;
    IF v_sev IS NULL THEN
        RAISE EXCEPTION 'Unknown rule id %', p_rule;
    END IF;
    v_status := CASE WHEN p_failed = 0 THEN 'pass'
                     WHEN v_sev = 'error' THEN 'fail'
                     WHEN v_sev = 'warning' THEN 'warn'
                     ELSE 'info' END;
    INSERT INTO dq.check_result (run_label, rule_id, rows_tested, rows_failed, pct_failed, status, detail)
    VALUES (p_run, p_rule, p_tested, p_failed,
            CASE WHEN p_tested = 0 THEN 0 ELSE round(100.0 * p_failed / p_tested, 3) END,
            v_status, p_detail);
END;
$$;
