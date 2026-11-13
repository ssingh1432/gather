#!/usr/bin/env python3
"""Apply pending SQL migrations from database/migrations to Supabase.

Uses the Supabase Management API (HTTPS), so no DB password / pooler is needed.

Env:
  SUPABASE_ACCESS_TOKEN   personal access token (required)
  SUPABASE_PROJECT_REF    project ref (required)

Tracking lives in public.repo_migrations(filename, checksum, applied_at).
Each pending file runs together with its tracking INSERT in ONE request, so a
failure rolls the whole file back and CI stops before deploying the app.

Safety: if the tracking table is empty the script refuses to run (it would
replay every historical migration). Seed a baseline first.
"""
import hashlib
import json
import os
import pathlib
import sys
import urllib.error
import urllib.request

MIG_DIR = pathlib.Path(__file__).resolve().parent.parent / "database" / "migrations"


def run_sql(token: str, ref: str, query: str):
    req = urllib.request.Request(
        f"https://api.supabase.com/v1/projects/{ref}/database/query",
        data=json.dumps({"query": query}).encode(),
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "User-Agent": "gather-ci/1.0",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            body = r.read().decode() or "[]"
            return json.loads(body)
    except urllib.error.HTTPError as e:
        raise SystemExit(f"Supabase API error {e.code}: {e.read().decode()[:2000]}")


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    token = os.environ.get("SUPABASE_ACCESS_TOKEN")
    ref = os.environ.get("SUPABASE_PROJECT_REF")
    if not token or not ref:
        print("SUPABASE_ACCESS_TOKEN and SUPABASE_PROJECT_REF are required", file=sys.stderr)
        return 2

    files = sorted(MIG_DIR.glob("*.sql"))
    rows = run_sql(token, ref, "select filename, checksum from public.repo_migrations")
    applied = {r["filename"]: r["checksum"] for r in rows}
    if not applied:
        print("repo_migrations is empty - refusing to replay history. Seed a baseline first.", file=sys.stderr)
        return 2

    for f in files:
        if f.name in applied and applied[f.name] != sha(f):
            print(f"::warning::{f.name} was edited after being applied (checksum differs). "
                  "Add a NEW migration instead of editing applied ones.")

    pending = [f for f in files if f.name not in applied]
    if not pending:
        print("No pending migrations.")
        return 0

    for f in pending:
        print(f"Applying {f.name} ...")
        sql = f.read_text(encoding="utf-8")
        name = f.name.replace("'", "''")
        run_sql(token, ref,
                f"{sql}\n;\ninsert into public.repo_migrations(filename, checksum) values ('{name}', '{sha(f)}');")
        print(f"  ok: {f.name}")
    print(f"Applied {len(pending)} migration(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
