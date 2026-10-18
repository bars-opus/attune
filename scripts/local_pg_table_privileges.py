#!/usr/bin/env python3
"""Print every table-level GRANT/REVOKE the migrations make, in order.

Run by local_pg_setup.sh after local_pg_grants.sql. That file blanket-grants
authenticated after the migrations, which silently undoes a REVOKE made in
an ordinary migration; in production Supabase grants once, at CREATE time,
so a later REVOKE stands (sync audit I-6, 2026-10-18). Replaying every
table statement in migration order reproduces production. Function,
sequence and schema statements are left to local_pg_grants.sql.
"""
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "supabase/migrations")
DOLLAR = re.compile(r"(\$[A-Za-z_]*\$).*?\1", re.S)
STATEMENT = re.compile(r"\b(GRANT|REVOKE)\b[^;]*;", re.I | re.S)
TARGET = re.compile(r"\bON\s+(TABLE\s+)?(public\.)?[A-Za-z_][A-Za-z0-9_]*\b", re.I)
NOT_TABLE = re.compile(r"\bON\s+(FUNCTIONS?|ROUTINES?|PROCEDURE|SEQUENCES?|SCHEMA|ALL|DATABASE|TYPES?|LARGE|TABLES)\b", re.I)

for path in sorted(root.glob("*.sql")):
    text = path.read_text()
    text = DOLLAR.sub(" ", text)
    text = "\n".join(line.split("--", 1)[0] for line in text.splitlines())
    for m in STATEMENT.finditer(text):
        stmt = " ".join(m.group(0).split())
        if NOT_TABLE.search(stmt) or not TARGET.search(stmt):
            continue
        if " TO " not in stmt.upper() and " FROM " not in stmt.upper():
            continue
        print(f"-- {path.name}\n{stmt}")
