---
name: duckdb
description: >-
  Queries, inspects, transforms, and converts local structured and
  semi-structured data files (JSON, JSONL, NDJSON, CSV, TSV, Parquet, SQLite),
  unified code diffs, and Markdown documents on Linux and macOS with DuckDB SQL.
  Use when querying local JSON, CSV, or SQLite files, benchmark artifacts, large
  code diffs, or Markdown corpora, inspecting schemas and row counts, searching
  and joining JSONL log globs with SQLite index databases (such as
  transcript.jsonl and conversation_summaries.db), joining files across formats,
  converting datasets to Parquet, or filtering stdin pipelines. Prefer it over
  ad hoc Python or jq for filtering, grouping, and joining local data. Don't use
  for remote cloud data warehouses (BigQuery, Snowflake, Spanner) or PLx
  dashboards.
key_features:
  - Non-interactive subshell flag safety (-batch -dark-mode)
  - Fast JSONL, CSV, Parquet, and SQLite querying
  - Explicit schema projection & multi-file globbing
  - Cross-format SQL joins & Parquet materialization
  - Relational code diff querying (scripts/diff_macros.sql)
  - Relational Markdown indexing (scripts/markdown_macros.sql)
---

# DuckDB CLI Analytics

Fast analytical SQL engine for querying, analyzing, and converting local data
files (JSON, JSONL, CSV, TSV, Parquet, SQLite), unified code diffs, and Markdown
documents directly from the shell without database servers or external imports.

## Quick Start & Execution Setup

DuckDB runs as a standalone CLI binary. Always invoke `duckdb` with
**`-batch -dark-mode`**.

### Installation & Subshell PATH Setup (Linux & macOS)

To prevent `exit code 127: duckdb: command not found` in non-interactive agent
subshells (where `mise` or `asdf` shims are not sourced):

- **`mise` shims on `PATH` (Recommended)**: If `mise` manages `duckdb`, put
  `~/.local/share/mise/shims` on `PATH` in the files non-interactive shells
  actually read (`~/.zshenv` / `BASH_ENV`, and `~/.config/environment.d/*.conf`
  for `systemd` user units) rather than symlinking each tool. The shims are
  symlinks to the `mise` binary itself, so they resolve even when `mise` is not
  on `PATH`, and one entry covers every managed tool. Keep `~/.local/bin`
  _before_ the shims dir so custom wrappers still win.

- **Direct Binary / Symlink (fallback)**: Where shims are unavailable, make the
  binary directly accessible at `~/.local/bin/duckdb` (or
  `/opt/homebrew/bin/duckdb` on Apple Silicon macOS). Note that a per-tool
  symlink collides with any dotfiles repo that tracks the same path:

  ```bash
  # Option A: If installed via mise, symlink into ~/.local/bin/
  ln -sf ~/.local/share/mise/installs/duckdb/latest/duckdb ~/.local/bin/duckdb

  # Option B: macOS Homebrew
  brew install duckdb

  # Option C: Direct download from GitHub Releases (Linux amd64)
  curl -LO https://github.com/duckdb/duckdb/releases/latest/download/duckdb_cli-linux-amd64.zip
  unzip -o duckdb_cli-linux-amd64.zip -d ~/.local/bin/
  ```

### Critical Flags

- `-batch -dark-mode` _(MANDATORY together in subshells)_:
  - `-dark-mode`: DuckDB attempts to detect terminal background color via OSC
    query sequences on startup. In non-interactive agent subshells, this probe
    times out after **5 seconds**
    (`Timeout trying to read terminal background color (> 5s elapsed)`).
    **`-batch` alone does NOT disable this probe** — `-dark-mode` (or
    `-light-mode`) is strictly required.
  - `-batch`: Disables interactive progress bars and prompt formatting.
- Output formatting:
  - `-box` _(Default)_: Clean Unicode boxed tables, ideal for terminal viewing.
  - `-json`: Output rows as JSON array of objects (ideal for piping to scripts).
  - `-csv`: Output standard comma-separated values with headers.
  - `-markdown`: Output standard markdown pipe tables.
  - `-bail`: Stop execution immediately on first error.

```bash
# Human-readable boxed table (non-interactive safe, zero 5s hang)
duckdb -batch -dark-mode -box -c "SELECT 42 AS answer;"

# Programmatic JSON output
duckdb -batch -dark-mode -json -c "SELECT 42 AS answer;"
```

---

## Core Gotchas & Invariants

1.  **5-Second Hang on Subshells (`-batch -dark-mode` Required)**: Passing
    `-batch` alone does **not** disable DuckDB's 5-second OSC terminal
    background color probe timeout. Always pass `-batch -dark-mode` together.
2.  **1-Based Array Indexing**: DuckDB follows ANSI SQL standards: `arr[1]` is
    the first element. `arr[0]` produces an out-of-bounds error.
3.  **Heterogeneous JSON Schemas**: When reading JSONL with varying keys across
    rows, DuckDB defaults to a common schema and may drop disparate keys. Pass
    `union_by_name = true` inside `read_json` or `read_json_auto`.
4.  **Interrupted / Malformed JSON Lines**: In log files or interrupted
    processes, malformed lines will abort the query. Pass
    `ignore_errors = true`.
5.  **Transparent Compression**: Files ending in `.gz` or `.zst` are read
    automatically without manual decompression.
6.  **Explicit `columns={...}` Projection & `STRUCT` vs. `JSON` Scalar Gotcha**:
    When scanning thousands of JSONL files (e.g. `transcript.jsonl`), passing an
    explicit `columns={...}` map skips multi-file schema inference and speeds up
    scans by **3x** (~1.1s -> ~0.39s). However, if you type a nested
    object/array column as `'JSON'` or `'JSON[]'`, DuckDB returns raw
    JSON-encoded scalars (with quotes inside the string, e.g.,
    `"\"run_command\""`), and comparing `tc.name = 'run_command'` fails with
    `Malformed JSON at byte 0 of input: unexpected character. Input: "run_command"`.
    - **Fix**: Always type nested objects explicitly as `STRUCT(...)[]` (e.g.
      `columns={'tool_calls': 'STRUCT(name VARCHAR, args JSON)[]'}`) OR extract
      strings using the `->>` operator (`tc->>'name' = 'run_command'`).
7.  **`.db` File Extension Disambiguation (DuckDB vs. SQLite)**: Both native
    DuckDB databases and SQLite databases frequently use `.db` extensions.
    Attempting `ATTACH 'path/to/file.db' AS db (TYPE SQLITE)` on a native DuckDB
    database fails with `file is not a database`. Run `file path/to/file.db`
    first when the format is unknown.

---

## Quick Format & Streaming Patterns

### 1. JSON / JSONL & Nested Unnesting

```bash
# Preview JSONL with irregular schema / interrupted lines tolerance
duckdb -batch -dark-mode -box -c "
SELECT * FROM read_json('logs/*.jsonl', union_by_name=true, ignore_errors=true) LIMIT 10;
"

# Dot access, 1-based array indexing, and unnest()
duckdb -batch -dark-mode -box -c "
SELECT id, user.email, tags[1] AS primary_tag, unnest(tags) AS tag FROM 'users.jsonl';
"
```

### 2. CSV, TSV & Parquet

```bash
# Auto-detect CSV/TSV or read compressed .csv.gz directly
duckdb -batch -dark-mode -box -c "SELECT * FROM 'export.csv.gz' LIMIT 10;"

# Read Parquet globs and inspect schema without scanning rows
duckdb -batch -dark-mode -box -c "
SELECT * FROM 'metrics/*.parquet' WHERE value > 100 LIMIT 10;
SELECT * FROM parquet_schema('metrics/part-00.parquet');
"
```

### 3. Standard Input Streaming (`/dev/stdin`)

```bash
curl -s "https://api.example.com/items" | \
  duckdb -batch -dark-mode -box -c "SELECT * FROM read_json('/dev/stdin') LIMIT 10;"
```

### 4. Local Databases (`.db`, `.duckdb`, `.sqlite`)

Always check `file path/to/database.db` first:

```bash
# Native DuckDB database file
duckdb -batch -dark-mode -box path/to/database.db -c "SHOW TABLES;"

# SQLite 3.x database file
duckdb -batch -dark-mode -box -c "
ATTACH 'path/to/database.db' AS db (TYPE SQLITE, READ_ONLY);
SELECT * FROM db.my_table LIMIT 10;
"
```

---

## SQL Cookbook & Advanced Recipes

Read [`references/recipes.md`](references/recipes.md),
[`scripts/diff_macros.sql`](scripts/diff_macros.sql), and
[`scripts/markdown_macros.sql`](scripts/markdown_macros.sql) for detailed SQL
cookbook patterns:

- **Agent Conversation Transcript Mining & SQLite Index Joins**: Fast-path
  `columns={...}` projection across
  `~/.gemini/*/brain/*/.system_generated/logs/transcript.jsonl` and
  `~/.claude/projects/**/*.jsonl`, searching and joining JSONL log globs with
  SQLite index databases (`ATTACH ... (TYPE SQLITE, READ_ONLY)`, such as joining
  `transcript.jsonl` with `conversation_summaries.db`), tool usage/error audits,
  and stripping `EPHEMERAL_MESSAGE` `<memory>` echoes.
- **Format Conversions & Parquet Materialization**: Converting JSONL/CSV logs to
  ZSTD Parquet (`COPY ... TO`), Hive-partitioned reads/writes, and cross-format
  SQL joins (JSON + CSV + Parquet + SQLite).
- **Benchmark JSON & Log Extraction**: Piping `<<<BENCH_PRESS_JSON_START>>>` log
  blocks into DuckDB, pivoting multi-target (`aot` / `jit` / `wasm`) benchmark
  JSON artifacts, and tuning memory/thread limits for `>10GB` datasets.
- **Relational Code Diff Querying**: Querying unified code diffs
  (`read_diff_lines`, `read_diff_hunks`) with
  [`scripts/diff_macros.sql`](scripts/diff_macros.sql).
- **Relational Markdown Indexing**: Indexing Markdown section hierarchies and
  fenced code blocks (`read_md_sections`, `read_md_code_blocks`) across large
  documents (`>= 350` lines) and multi-file corpora (`10+` files) with
  [`scripts/markdown_macros.sql`](scripts/markdown_macros.sql).
