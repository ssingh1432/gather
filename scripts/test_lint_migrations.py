#!/usr/bin/env python3
"""Unit tests for scripts/lint_migrations.py plus a gate on the real repo.

Run: python3 -m unittest scripts/test_lint_migrations.py -v
"""
import importlib.util
import pathlib
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("lint", HERE / "lint_migrations.py")
lint = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lint)


class LintOnFixtures(unittest.TestCase):
    def run_lint(self, files):
        with tempfile.TemporaryDirectory() as d:
            mig = pathlib.Path(d)
            for name, sql in files.items():
                (mig / name).write_text(sql)
            old_mig, old_allow = lint.MIG, lint.ALLOW
            lint.MIG, lint.ALLOW = mig, mig / "none.txt"
            try:
                return lint.lint()
            finally:
                lint.MIG, lint.ALLOW = old_mig, old_allow

    def test_table_without_rls_is_error(self):
        errs, _ = self.run_lint({"001_a.sql": "create table public.t (id int);"})
        self.assertTrue(any("E1" in e and "public.t" in e for e in errs))

    def test_table_with_rls_in_later_file_passes(self):
        errs, _ = self.run_lint({
            "001_a.sql": "create table public.t (id int);",
            "002_b.sql": "alter table public.t enable row level security;",
        })
        self.assertEqual(errs, [])

    def test_commented_rls_does_not_count(self):
        errs, _ = self.run_lint({
            "001_a.sql": "create table public.t (id int);\n-- alter table public.t enable row level security;",
        })
        self.assertEqual(len(errs), 1)

    def test_security_definer_requires_search_path(self):
        bad = "create function public.f() returns void language plpgsql security definer as $$ begin end; $$;"
        good = "create function public.g() returns void language plpgsql security definer set search_path = public as $$ begin end; $$;"
        errs, _ = self.run_lint({"001_a.sql": bad + "\n" + good})
        self.assertEqual([e for e in errs if "E2" in e and " f " in e + " "], [e for e in errs if "E2" in e])
        self.assertFalse(any(" g " in e for e in errs))

    def test_bad_filename_is_error(self):
        errs, _ = self.run_lint({"notes.sql": "select 1;"})
        self.assertTrue(any("E3" in e for e in errs))

    def test_function_revoke_without_public_warns_until_public_revoked(self):
        _, w = self.run_lint({"001_a.sql": "revoke all on function public.f() from anon, authenticated;"})
        self.assertTrue(any("W1" in x for x in w))
        _, w = self.run_lint({
            "001_a.sql": "revoke all on function public.f() from anon, authenticated;",
            "002_b.sql": "revoke all on function public.f() from public, anon, authenticated;",
        })
        self.assertFalse(any("W1" in x for x in w))


class RealRepoGate(unittest.TestCase):
    def test_repo_migrations_have_no_lint_errors(self):
        errs, _ = lint.lint()
        self.assertEqual(errs, [], "\n".join(errs))


if __name__ == "__main__":
    unittest.main()
