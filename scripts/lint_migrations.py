#!/usr/bin/env python3
"""Lint database/migrations.

Fails on:
  * a NEW migration whose numeric prefix is already used by another file
    (historical duplicates are allow-listed in LEGACY_DUPLICATE_PREFIXES);
  * a migration file that is not named NNN[a-z]_description.sql;
  * a NEW migration that creates a table in `public` but never mentions
    GRANT (Postgres checks table GRANTs before RLS -> 42501 errors) or
    never enables row level security.

"New" means the file is not in LEGACY_FILES (the set present when the lint
was introduced). Existing files are never rewritten: renaming an applied
migration would change its tracking key in public.repo_migrations.
"""
import pathlib
import re
import sys
from collections import defaultdict

MIG_DIR = pathlib.Path(__file__).resolve().parent.parent / "database" / "migrations"
NAME_RE = re.compile(r"^(\d{3})([a-z]?)_[a-z0-9_]+\.sql$")
LEGACY_CUTOFF = 126  # every migration numbered <= 126 predates this lint
CREATE_TABLE_RE = re.compile(r"create\s+table\s+(?:if\s+not\s+exists\s+)?(?:public\.)?([a-z_0-9]+)", re.I)


def main() -> int:
    errors, warnings = [], []
    by_prefix = defaultdict(list)
    for f in sorted(MIG_DIR.glob("*.sql")):
        m = NAME_RE.match(f.name)
        if not m:
            errors.append(f"{f.name}: name must match NNN[a-z]_description.sql")
            continue
        num = int(m.group(1))
        by_prefix[m.group(1) + m.group(2)].append(f.name)
        if num <= LEGACY_CUTOFF:
            continue
        sql = f.read_text()
        low = sql.lower()
        tables = CREATE_TABLE_RE.findall(sql)
        if tables and "grant " not in low:
            errors.append(f"{f.name}: creates table(s) {sorted(set(tables))} but has no GRANT")
        if tables and "enable row level security" not in low:
            errors.append(f"{f.name}: creates table(s) {sorted(set(tables))} but never enables RLS")
    for prefix, files in by_prefix.items():
        if len(files) > 1 and int(prefix[:3]) > LEGACY_CUTOFF:
            errors.append(f"duplicate prefix {prefix}: {files}")
        elif len(files) > 1:
            warnings.append(f"legacy duplicate prefix {prefix}: {files}")
    for w in warnings:
        print(f"::notice::{w}")
    for e in errors:
        print(f"::error::{e}")
    print(f"checked {sum(len(v) for v in by_prefix.values())} migrations, {len(errors)} error(s), {len(warnings)} legacy warning(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
