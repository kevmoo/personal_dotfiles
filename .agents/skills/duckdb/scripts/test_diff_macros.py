#!/usr/bin/env python3
"""Unit tests for skills/duckdb/scripts/diff_macros.sql."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from typing import Any

SCRIPTS_DIR = Path(__file__).resolve().parent
MACROS_SQL = SCRIPTS_DIR / "diff_macros.sql"


def _find_duckdb() -> str | None:
    """Finds the duckdb CLI executable on PATH or in ~/.local/bin."""
    found = shutil.which("duckdb")
    if found:
        return found
    candidate = Path.home() / ".local/bin/duckdb"
    if candidate.is_file() and os.access(candidate, os.X_OK):
        return str(candidate)
    return None


DUCKDB_BIN = _find_duckdb()


@unittest.skipUnless(DUCKDB_BIN, "duckdb CLI binary not found")
class TestDiffMacros(unittest.TestCase):
    def setUp(self) -> None:
        self.test_dir = tempfile.mkdtemp()

    def tearDown(self) -> None:
        shutil.rmtree(self.test_dir)

    def _query(self, sql: str) -> list[dict[str, Any]]:
        """Executes a SQL query with diff_macros.sql initialized and returns JSON rows."""
        res = subprocess.run(
            [
                str(DUCKDB_BIN),
                "-batch",
                "-dark-mode",
                "-json",
                "-init",
                str(MACROS_SQL),
                "-c",
                sql,
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        out = res.stdout.strip()
        return json.loads(out) if out else []

    def test_read_diff_lines_and_hunks(self) -> None:
        diff_content = (
            "diff --git a/src/service.py b/src/service.py\n"
            "index 1111111..2222222 100644\n"
            "--- a/src/service.py\n"
            "+++ b/src/service.py\n"
            "@@ -10,3 +10,4 @@ def process():\n"
            " keep_before\n"
            "-old_call()\n"
            "+new_call()\n"
            "+extra_call()\n"
            " keep_after\n"
            "diff --git a/tests/test_service.py b/tests/test_service.py\n"
            "--- a/tests/test_service.py\n"
            "+++ b/tests/test_service.py\n"
            "@@ -1 +1,2 @@\n"
            " assert True\n"
            "+new_call()\n"
        )
        raw_diff_path = Path(self.test_dir) / "sample.diff"
        raw_diff_path.write_text(diff_content, encoding="utf-8")

        raw_lines = self._query(
            f"SELECT file_path, hunk_id, func_context, op, old_line, new_line, content "
            f"FROM read_diff_lines('{raw_diff_path}');"
        )
        self.assertEqual(
            raw_lines,
            [
                {
                    "file_path": "src/service.py",
                    "hunk_id": 1,
                    "func_context": "def process():",
                    "op": " ",
                    "old_line": 10,
                    "new_line": 10,
                    "content": "keep_before",
                },
                {
                    "file_path": "src/service.py",
                    "hunk_id": 1,
                    "func_context": "def process():",
                    "op": "-",
                    "old_line": 11,
                    "new_line": None,
                    "content": "old_call()",
                },
                {
                    "file_path": "src/service.py",
                    "hunk_id": 1,
                    "func_context": "def process():",
                    "op": "+",
                    "old_line": None,
                    "new_line": 11,
                    "content": "new_call()",
                },
                {
                    "file_path": "src/service.py",
                    "hunk_id": 1,
                    "func_context": "def process():",
                    "op": "+",
                    "old_line": None,
                    "new_line": 12,
                    "content": "extra_call()",
                },
                {
                    "file_path": "src/service.py",
                    "hunk_id": 1,
                    "func_context": "def process():",
                    "op": " ",
                    "old_line": 12,
                    "new_line": 13,
                    "content": "keep_after",
                },
                {
                    "file_path": "tests/test_service.py",
                    "hunk_id": 2,
                    "func_context": "",
                    "op": " ",
                    "old_line": 1,
                    "new_line": 1,
                    "content": "assert True",
                },
                {
                    "file_path": "tests/test_service.py",
                    "hunk_id": 2,
                    "func_context": "",
                    "op": "+",
                    "old_line": None,
                    "new_line": 2,
                    "content": "new_call()",
                },
            ],
        )

        raw_hunks = self._query(
            f"SELECT file_path, hunk_id, old_start, old_count, new_start, new_count, "
            f"func_context, added_lines, deleted_lines "
            f"FROM read_diff_hunks('{raw_diff_path}');"
        )
        self.assertEqual(
            raw_hunks,
            [
                {
                    "file_path": "src/service.py",
                    "hunk_id": 1,
                    "old_start": 10,
                    "old_count": 3,
                    "new_start": 10,
                    "new_count": 4,
                    "func_context": "def process():",
                    "added_lines": 2,
                    "deleted_lines": 1,
                },
                {
                    "file_path": "tests/test_service.py",
                    "hunk_id": 2,
                    "old_start": 1,
                    "old_count": 1,
                    "new_start": 1,
                    "new_count": 2,
                    "func_context": "",
                    "added_lines": 1,
                    "deleted_lines": 0,
                },
            ],
        )

    def test_sql_comment_and_plusplus_lines_inside_hunks(self) -> None:
        diff_content = (
            "diff --git a/schema.sql b/schema.sql\n"
            "--- a/schema.sql\n"
            "+++ b/schema.sql\n"
            "@@ -1,3 +1,3 @@\n"
            "--- old sql comment\n"
            "+-- new sql comment\n"
            "+++ counter_note\n"
            "--- a/fake_header_inside_hunk\n"
            " SELECT 1;\n"
        )
        raw_diff_path = Path(self.test_dir) / "comments.diff"
        raw_diff_path.write_text(diff_content, encoding="utf-8")

        lines = self._query(
            f"SELECT file_path, hunk_id, op, old_line, new_line, content "
            f"FROM read_diff_lines('{raw_diff_path}');"
        )
        self.assertEqual(
            lines,
            [
                {
                    "file_path": "schema.sql",
                    "hunk_id": 1,
                    "op": "-",
                    "old_line": 1,
                    "new_line": None,
                    "content": "-- old sql comment",
                },
                {
                    "file_path": "schema.sql",
                    "hunk_id": 1,
                    "op": "+",
                    "old_line": None,
                    "new_line": 1,
                    "content": "-- new sql comment",
                },
                {
                    "file_path": "schema.sql",
                    "hunk_id": 1,
                    "op": "+",
                    "old_line": None,
                    "new_line": 2,
                    "content": "++ counter_note",
                },
                {
                    "file_path": "schema.sql",
                    "hunk_id": 1,
                    "op": "-",
                    "old_line": 2,
                    "new_line": None,
                    "content": "-- a/fake_header_inside_hunk",
                },
                {
                    "file_path": "schema.sql",
                    "hunk_id": 1,
                    "op": " ",
                    "old_line": 3,
                    "new_line": 3,
                    "content": "SELECT 1;",
                },
            ],
        )

        hunks = self._query(
            f"SELECT file_path, added_lines, deleted_lines FROM read_diff_hunks('{raw_diff_path}');"
        )
        self.assertEqual(
            hunks,
            [
                {
                    "file_path": "schema.sql",
                    "added_lines": 2,
                    "deleted_lines": 2,
                }
            ],
        )

    def test_new_and_deleted_files(self) -> None:
        diff_content = (
            "diff --git a/src/old.py b/src/old.py\n"
            "deleted file mode 100644\n"
            "--- a/src/old.py\n"
            "+++ /dev/null\n"
            "@@ -1,2 +0,0 @@\n"
            "-line_a\n"
            "-line_b\n"
            "diff --git a/src/new.py b/src/new.py\n"
            "new file mode 100644\n"
            "--- /dev/null\n"
            "+++ b/src/new.py\n"
            "@@ -0,0 +1,1 @@\n"
            "+created_line\n"
        )
        raw_diff_path = Path(self.test_dir) / "new_del.diff"
        raw_diff_path.write_text(diff_content, encoding="utf-8")

        lines = self._query(
            f"SELECT file_path, op, old_line, new_line, content "
            f"FROM read_diff_lines('{raw_diff_path}');"
        )
        self.assertEqual(
            lines,
            [
                {
                    "file_path": "src/old.py",
                    "op": "-",
                    "old_line": 1,
                    "new_line": None,
                    "content": "line_a",
                },
                {
                    "file_path": "src/old.py",
                    "op": "-",
                    "old_line": 2,
                    "new_line": None,
                    "content": "line_b",
                },
                {
                    "file_path": "src/new.py",
                    "op": "+",
                    "old_line": None,
                    "new_line": 1,
                    "content": "created_line",
                },
            ],
        )


if __name__ == "__main__":
    unittest.main()
