/*
  03_raw_load.sql
  Purpose : Load data/raw/moa-open-data.csv into the raw table without changing it.

  Run this from the repository root so the relative path below resolves.

  Why \copy and not COPY:
    \copy is a psql client command. It reads the file from the machine running psql, so it
    works without database-server file permissions. Plain COPY reads from the server machine.

  Why ENCODING 'WIN1252':
    The file is not UTF-8. The euro sign is stored as the single byte 0x80, which is how
    Windows-1252 encodes it. Telling the database the true encoding converts it correctly
    to a euro sign in the database, while the file on disk stays byte-for-byte untouched.
    Loading it as UTF-8 fails with "invalid byte sequence", and a silent wrong guess would
    corrupt the observation_type text.

  Why HEADER true:
    The first line is skipped. Columns are mapped by position using the column list below,
    so the odd source header (spaces, padded name) does not matter.

  Idempotent: the table is emptied first, and the identity counter restarts, so rerunning
  gives the same raw_row_id for the same row.
*/

TRUNCATE TABLE raw.cbi_mortgage_arrears_open_data RESTART IDENTITY;

\copy raw.cbi_mortgage_arrears_open_data (reporting_date, entity_group, format_code, category, row_position, column_position, row_label, observation_type, observation, number_of_accounts) FROM 'data/raw/moa-open-data.csv' WITH (FORMAT csv, HEADER true, ENCODING 'WIN1252')
