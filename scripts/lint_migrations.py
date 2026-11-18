#!/usr/bin/env python3
"""Static safety lint for database/migrations/*.sql (Phase 17).

Runs without a database, so it is safe in CI on every pull request.

Checks (each maps to a real incident documented in docs/DATABASE.md §9):
  E1  every `create table public.X` has `enable row level security` for X
      somewhere in the migration set (a table without RLS is world-readable
      through PostgREST once granted).
  E2  every `security definer` function sets `search_path` (prevents
      search-path hijacking).
  E3  numbered filenames parse (NNN[a|b]_name.sql) so apply order is defined.
  W1  `revoke ... from anon, authenticated` on a *function* should also name
      `public` (migration 040 lesson: PUBLIC keeps EXECUTE otherwise).
  W2  duplicate numeric prefixes (allowed historically, flagged for awareness).

Exit code 1 on any E*, 0 otherwise. Use --strict to fail on W* as well.
Known, reviewed exceptions live in scripts/lint_migrations_allowlist.txt
as `CODE:identifier` lines.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MIG = ROOT / "database" / "migrations"
ALLOW = ROOT / "scripts" / "lint_migrations_allowlist.txt"
NAME_RE = re.compile(r"^(\d{3})([a-z]?)_[a-z0-9_]+\.sql$")


def strip_comments(sql: str) -> str:
    sql = re.sub(r"/\*.*?\*/", "", sql, flags=re.S)
    return re.sub(r"--[^\n]*", "", sql)


def load_allow():
    if not ALLOW.exists():
        return set()
    return {l.strip() for l in ALLOW.read_text().splitlines()
            if l.strip() and not l.startswith("#")}


def lint():
    errors, warnings = [], []
    allow = load_allow()
    files = sorted(MIG.glob("*.sql"))
    texts = {f.name: strip_comments(f.read_text(errors="replace")) for f in files}
    all_sql = "\n".join(texts.values())

    created = {}
    for name, sql in texts.items():
        for m in re.finditer(
            r"create\s+table\s+(?:if\s+not\s+exists\s+)?public\.([a-z_0-9]+)", sql, re.I
        ):
            created.setdefault(m.group(1), name)
    rls_on = {
        m.group(1)
        for m in re.finditer(
            r"alter\s+table\s+(?:if\s+exists\s+)?(?:only\s+)?public\.([a-z_0-9]+)\s+enable\s+row\s+level\s+security",
            all_sql, re.I)
    }
    dropped = {
        m.group(1)
        for m in re.finditer(r"drop\s+table\s+(?:if\s+exists\s+)?public\.([a-z_0-9]+)", all_sql, re.I)
    }
    for table, name in sorted(created.items()):
        if table not in rls_on and table not in dropped and f"E1:{table}" not in allow:
            errors.append(f"E1 {name}: table public.{table} never enables RLS")

    for name, sql in texts.items():
        # split into function statements roughly by "create ... function"
        for stmt in re.split(r"(?=create\s+(?:or\s+replace\s+)?function)", sql, flags=re.I):
            head = re.match(
                r"create\s+(?:or\s+replace\s+)?function\s+(?:public\.)?([a-z_0-9]+)", stmt, re.I)
            if not head:
                continue
            fn = head.group(1)
            header = stmt.split("$$", 1)[0] if "$$" in stmt else stmt[:1500]
            if re.search(r"security\s+definer", header, re.I) and not re.search(
                r"set\s+search_path", header, re.I
            ):
                if f"E2:{fn}" not in allow:
                    errors.append(f"E2 {name}: security definer function {fn} has no SET search_path")

    prefixes = {}
    for f in files:
        m = NAME_RE.match(f.name)
        if not m:
            if f"E3:{f.name}" not in allow:
                errors.append(f"E3 {f.name}: filename does not match NNN[a-z]_name.sql")
            continue
        prefixes.setdefault(m.group(1) + m.group(2), []).append(f.name)
    for p, names in sorted(prefixes.items()):
        if len(names) > 1:
            warnings.append(f"W2 duplicate prefix {p}: {', '.join(names)}")

    # W1: a function whose EXECUTE is revoked from anon/authenticated must
    # also be revoked from PUBLIC somewhere in the set (migration 040 lesson).
    public_revoked = set()
    for m in re.finditer(r"revoke\s+[^;]*?on\s+function\s+(?:public\.)?([a-z_0-9]+)[^;]*?from\s+([^;]+);", all_sql, re.I):
        if re.search(r"\bpublic\b", m.group(2), re.I):
            public_revoked.add(m.group(1))
    for name, sql in texts.items():
        for m in re.finditer(r"revoke\s+[^;]*?on\s+function\s+(?:public\.)?([a-z_0-9]+)[^;]*?from\s+([^;]+);", sql, re.I):
            targets = m.group(2).lower()
            if "anon" in targets and not re.search(r"\bpublic\b", targets) and m.group(1) not in public_revoked:
                warnings.append(f"W1 {name}: {m.group(1)} revoked from anon without PUBLIC")
    return errors, warnings


if __name__ == "__main__":
    errs, warns = lint()
    for w in warns:
        print("warning:", w)
    for e in errs:
        print("error:", e)
    print(f"{len(list(MIG.glob('*.sql')))} migrations, {len(errs)} errors, {len(warns)} warnings")
    sys.exit(1 if errs or (warns and "--strict" in sys.argv) else 0)
