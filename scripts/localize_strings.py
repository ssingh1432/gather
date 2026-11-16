#!/usr/bin/env python3
"""Replace hard-coded UI string literals with AppL10n lookups and register the keys.

Usage: localize_strings.py <table.py> <dart files...>
The table defines TABLE = [(key, en, ne), ...]. Keys already in app_l10n.dart are reused.
Replaces exact string-literal tokens with `AppL10n.of(context).<getter>`, strips `const`
from enclosing constructors/collections, and refuses (reports) enclosing const declarations.
"""
import re, sys, importlib.util, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent / "flutter_app" / "lib"
L10N = ROOT / "core" / "l10n" / "app_l10n.dart"

def camel(k):
    p = k.split("_"); return p[0] + "".join(x.capitalize() for x in p[1:])

def esc(s): return s.replace("\\", "\\\\").replace("'", "\\'").replace("$", "\\$")

def load_table(path):
    spec = importlib.util.spec_from_file_location("tbl", path)
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
    return m.TABLE

def register(table):
    s = L10N.read_text()
    existing = set(re.findall(r"^\s+'([a-z0-9_]+)': '", s, re.M))
    getters, en_rows, ne_rows = [], [], []
    for key, en, ne in table:
        if key in existing: continue
        ph = sorted(set(re.findall(r"\{(\w+)\}", en)))
        if ph:
            params = ", ".join(f"Object {p}" for p in ph)
            amap = ", ".join(f"'{p}': {p}" for p in ph)
            getters.append(f"  String {camel(key)}({params}) => t('{key}', <String, Object?>{{{amap}}});")
        else:
            getters.append(f"  String get {camel(key)} => t('{key}');")
        en_rows.append(f"      '{key}': '{esc(en)}',")
        ne_rows.append(f"      '{key}': '{esc(ne)}',")
    if not getters: return
    marker = "\n  /// Translation tables."
    assert marker in s
    s = s.replace(marker, "\n".join(getters) + "\n" + marker, 1)
    en_end = "    },\n    'ne': <String, String>{"
    assert en_end in s
    s = s.replace(en_end, "\n".join(en_rows) + "\n" + en_end, 1)
    ne_end = "    },\n  };\n}"
    assert ne_end in s
    s = s.replace(ne_end, "\n".join(ne_rows) + "\n" + ne_end, 1)
    L10N.write_text(s)

def skip_string(t, i):
    q = t[i]; i += 1
    while i < len(t):
        if t[i] == "\\": i += 2; continue
        if t[i] == q: return i + 1
        i += 1
    return i

def enclosing_opens(t, pos):
    """Return positions of unclosed ( [ { before pos, innermost last."""
    stack = []; i = 0
    while i < pos:
        c = t[i]
        if c in "'\"": i = skip_string(t, i); continue
        if c == "/" and t[i:i+2] == "//":
            i = t.find("\n", i); i = len(t) if i < 0 else i; continue
        if c in "([{": stack.append(i)
        elif c in ")]}" and stack: stack.pop()
        i += 1
    return stack

def process(path, table):
    t = path.read_text()
    reps = []
    for key, en, ne in table:
        src = en.replace("\u2019", "\\u2019")
        for q in ("'", '"'):
            tok = q + src + q
            start = 0
            while True:
                i = t.find(tok, start)
                if i < 0: break
                reps.append((i, len(tok), key)); start = i + len(tok)
    # drop overlaps (prefer earlier/longer)
    reps.sort(key=lambda r: (r[0], -r[1]))
    clean, last = [], -1
    for r in reps:
        if r[0] >= last: clean.append(r); last = r[0] + r[1]
    if not clean: return 0, []
    const_spans, problems = set(), []
    for pos, ln, key in clean:
        for o in enclosing_opens(t, pos):
            before = t[max(0, o - 120):o]
            m = re.search(r"\bconst\s+(?:<[^<>()]*>\s*)?[A-Za-z_][\w.<>?]*\s*$", before) if t[o] == "(" else re.search(r"\bconst\s*(?:<[^<>]*>)?\s*$", before)
            if m:
                cm = re.search(r"\bconst\b", before[m.start():])
                s0 = o - len(before) + m.start() + cm.start()
                # declaration-level const (static const / const name =) cannot be stripped
                pre = t[max(0, s0 - 12):s0]
                if re.search(r"(static|final)\s*$", pre) or re.match(r"const\s+[A-Za-z_]\w*\s*=", t[s0:s0 + 80]):
                    problems.append((path.name, key, "inside const declaration")); break
                const_spans.add((s0, s0 + len("const")))
    if problems: return 0, problems
    # apply replacements and const removals, descending by position
    edits = [(p, p + l, "AppL10n.of(context)." + camel(k)) for p, l, k in clean]
    edits += [(a, b + (1 if t[b] == " " else 0), "") for a, b in const_spans]
    for a, b, new in sorted(edits, key=lambda e: -e[0]):
        t = t[:a] + new + t[b:]
    if "core/l10n/app_l10n.dart" not in t:
        depth = path.relative_to(ROOT).parts
        rel = "../" * (len(depth) - 1) + "core/l10n/app_l10n.dart"
        imp = f"import '{rel}';\n"
        m = re.search(r"^import .*;\n", t, re.M)
        t = t[:m.start()] + imp + t[m.start():] if m else imp + t
    path.write_text(t)
    return len(clean), []

if __name__ == "__main__":
    table = load_table(sys.argv[1])
    register(table)
    for f in sys.argv[2:]:
        n, probs = process(pathlib.Path(f).resolve(), table)
        print(f"{f}: {n} replacements", probs or "")
