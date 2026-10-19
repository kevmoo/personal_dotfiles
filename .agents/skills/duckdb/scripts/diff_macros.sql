-- Relational Code Diff Macros for DuckDB
-- Load with: duckdb -batch -dark-mode -init skills/duckdb/scripts/diff_macros.sql

-- Internal helper: Parse raw unified diff lines and classify file/hunk headers
CREATE OR REPLACE MACRO _parse_unified_diff(diff_path) AS TABLE
WITH raw_lines AS (
  SELECT
    row_number() OVER () AS row_id,
    rtrim(line, chr(13)) AS line
  FROM read_csv(
    diff_path,
    header=false,
    columns={'line': 'VARCHAR'},
    quote='',
    delim=chr(0),
    null_padding=true
  )
),
header_flags AS (
  SELECT
    row_id,
    line,
    (
      starts_with(line, '--- ')
      AND starts_with(lead(line, 1) OVER (ORDER BY row_id), '+++ ')
      AND starts_with(lead(line, 2) OVER (ORDER BY row_id), '@@ ')
    ) AS is_old_file_header,
    (
      starts_with(line, '+++ ')
      AND starts_with(lag(line, 1) OVER (ORDER BY row_id), '--- ')
      AND starts_with(lead(line, 1) OVER (ORDER BY row_id), '@@ ')
    ) AS is_new_file_header
  FROM raw_lines
),
classified AS (
  SELECT
    row_id,
    line,
    COALESCE(
      CASE
        WHEN is_new_file_header THEN COALESCE(
          NULLIF(regexp_extract(line, '^\+\+\+ "b/((?:[^"\\]|\\.)+)"', 1), ''),
          NULLIF(regexp_extract(line, '^\+\+\+ b/([^\t\r\n]+)', 1), '')
        )
      END,
      NULLIF(regexp_extract(line, '^diff --git (?:"a/[^"]+"|a/\S+) "b/((?:[^"\\]|\\.)+)"$', 1), ''),
      NULLIF(regexp_extract(line, '^diff --git (?:"a/[^"]+"|a/\S+) b/(\S+)$', 1), ''),
      CASE
        WHEN is_old_file_header THEN COALESCE(
          NULLIF(regexp_extract(line, '^--- "a/((?:[^"\\]|\\.)+)"', 1), ''),
          NULLIF(regexp_extract(line, '^--- a/([^\t\r\n]+)', 1), '')
        )
      END
    ) AS extracted_file,
    starts_with(line, '@@ ') AS is_hunk,
    (
      starts_with(line, 'diff --git ')
      OR starts_with(line, 'index ')
      OR is_old_file_header
      OR is_new_file_header
      OR starts_with(line, 'new file ')
      OR starts_with(line, 'deleted file ')
      OR starts_with(line, 'similarity index ')
      OR starts_with(line, 'rename from ')
      OR starts_with(line, 'rename to ')
      OR starts_with(line, 'old mode ')
      OR starts_with(line, 'new mode ')
      OR starts_with(line, 'Binary files ')
      OR starts_with(line, '\ No newline')
    ) AS is_meta
  FROM header_flags
)
SELECT
  row_id,
  line,
  is_hunk,
  is_meta,
  LAST_VALUE(extracted_file IGNORE NULLS) OVER (
    ORDER BY row_id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
  ) AS file_path,
  COUNT(*) FILTER (WHERE is_hunk) OVER (
    ORDER BY row_id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
  ) AS hunk_id
FROM classified;

-- 1. Parse raw unified diff lines directly from a .diff file or '/dev/stdin'
CREATE OR REPLACE MACRO read_diff_lines(diff_path) AS TABLE
WITH hunk_context AS (
  SELECT
    row_id,
    line,
    is_hunk,
    is_meta,
    file_path,
    hunk_id,
    FIRST_VALUE(
      CASE
        WHEN is_hunk THEN TRY_CAST(regexp_extract(line, '^@@ -(\d+)', 1) AS INTEGER)
        ELSE NULL
      END
    ) OVER (PARTITION BY hunk_id ORDER BY row_id) AS old_start,
    FIRST_VALUE(
      CASE
        WHEN is_hunk THEN TRY_CAST(regexp_extract(line, '^@@ -\d+(?:,\d+)? \+(\d+)', 1) AS INTEGER)
        ELSE NULL
      END
    ) OVER (PARTITION BY hunk_id ORDER BY row_id) AS new_start,
    FIRST_VALUE(
      CASE
        WHEN is_hunk THEN trim(regexp_extract(line, '^@@ -\d+(?:,\d+)? \+\d+(?:,\d+)? @@(.*)$', 1))
        ELSE NULL
      END
    ) OVER (PARTITION BY hunk_id ORDER BY row_id) AS func_context,
    left(line, 1) AS op,
    (hunk_id > 0 AND NOT is_hunk AND NOT is_meta AND left(line, 1) IN ('+', '-', ' ')) AS is_body
  FROM _parse_unified_diff(diff_path)
)
SELECT
  file_path,
  hunk_id,
  func_context,
  op,
  CASE
    WHEN op IN ('-', ' ') THEN old_start + COUNT(*) FILTER (WHERE is_body AND op IN ('-', ' ')) OVER (
      PARTITION BY hunk_id ORDER BY row_id ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    )
    ELSE NULL
  END AS old_line,
  CASE
    WHEN op IN ('+', ' ') THEN new_start + COUNT(*) FILTER (WHERE is_body AND op IN ('+', ' ')) OVER (
      PARTITION BY hunk_id ORDER BY row_id ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    )
    ELSE NULL
  END AS new_line,
  substr(line, 2) AS content
FROM hunk_context
WHERE is_body
ORDER BY row_id;

-- 2. Summarize hunks directly from a raw unified diff file or '/dev/stdin'
CREATE OR REPLACE MACRO read_diff_hunks(diff_path) AS TABLE
SELECT
  FIRST(file_path ORDER BY row_id) AS file_path,
  hunk_id,
  FIRST(TRY_CAST(regexp_extract(line, '^@@ -(\d+)', 1) AS INTEGER) ORDER BY row_id) AS old_start,
  FIRST(
    COALESCE(
      TRY_CAST(NULLIF(regexp_extract(line, '^@@ -\d+,(\d+)', 1), '') AS INTEGER),
      1
    ) ORDER BY row_id
  ) AS old_count,
  FIRST(TRY_CAST(regexp_extract(line, '^@@ -\d+(?:,\d+)? \+(\d+)', 1) AS INTEGER) ORDER BY row_id) AS new_start,
  FIRST(
    COALESCE(
      TRY_CAST(NULLIF(regexp_extract(line, '^@@ -\d+(?:,\d+)? \+\d+,(\d+)', 1), '') AS INTEGER),
      1
    ) ORDER BY row_id
  ) AS new_count,
  FIRST(trim(regexp_extract(line, '^@@ -\d+(?:,\d+)? \+\d+(?:,\d+)? @@(.*)$', 1)) ORDER BY row_id) AS func_context,
  COUNT(*) FILTER (WHERE NOT is_hunk AND NOT is_meta AND left(line, 1) = '+') AS added_lines,
  COUNT(*) FILTER (WHERE NOT is_hunk AND NOT is_meta AND left(line, 1) = '-') AS deleted_lines
FROM _parse_unified_diff(diff_path)
WHERE hunk_id > 0
GROUP BY hunk_id
ORDER BY hunk_id;
