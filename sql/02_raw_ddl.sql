/*
  02_raw_ddl.sql
  Purpose : Landing table for the Central Bank of Ireland file moa-open-data.csv.

  Design rules for the raw layer:
    1. Every source column is TEXT. No casting, trimming or parsing happens here, because
       any conversion could hide a defect (for example a stray space or a comma in a number).
       The source stores numbers like " 1,241 " as text, so the raw layer keeps them as text.
    2. No constraints on source columns, so a bad row can never block the load.
    3. Three audit columns are added by the database, not taken from the file:
         raw_row_id  = position of the row in the file (1 = first data row). This is the key
                       used later to trace any dashboard number back to its source row.
         source_file = name of the file the row came from.
         loaded_at   = when the row was loaded.
    4. Source column names are cleaned for SQL (the original header has spaces and a
       padded name " Number of Accounts "). The mapping is documented in docs/data_dictionary.md.
*/

DROP TABLE IF EXISTS raw.cbi_mortgage_arrears_open_data;

CREATE TABLE raw.cbi_mortgage_arrears_open_data (
    raw_row_id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source_file         TEXT        NOT NULL DEFAULT 'moa-open-data.csv',
    loaded_at           TIMESTAMPTZ NOT NULL DEFAULT now(),

    reporting_date      TEXT,   /* source: Reporting Date, format dd/mm/yyyy */
    entity_group        TEXT,   /* source: Entity Group, Banks or Non-Banks */
    format_code         TEXT,   /* source: Format, PDH or BTL */
    category            TEXT,   /* source: Category, the table block the row belongs to */
    row_position        TEXT,   /* source: Row Position */
    column_position     TEXT,   /* source: Column Position */
    row_label           TEXT,   /* source: Row, the line item description */
    observation_type    TEXT,   /* source: Observation Type, the metric and unit */
    observation         TEXT,   /* source: Observation, euro amounts (and sometimes counts) */
    number_of_accounts  TEXT    /* source: ' Number of Accounts ' (padded header), account counts */
);

COMMENT ON TABLE raw.cbi_mortgage_arrears_open_data IS
  'Verbatim load of Central Bank of Ireland moa-open-data.csv (CC BY 4.0). All source columns are text.';
COMMENT ON COLUMN raw.cbi_mortgage_arrears_open_data.raw_row_id IS
  'Row position in the source file, 1 = first data row after the header. Used for lineage.';
