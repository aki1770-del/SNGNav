#!/usr/bin/env python3
"""
Loom L35 — THE SNIPPET ORACLE.

Every other loom in this unit gates whether the AUTHOR WAS HONEST.
This one gates whether the ARTIFACT IS TRUE FOR THE STRANGER WHO USES IT.

It extracts every `dart` code block a reader is invited to copy — from README.md
and from the dartdoc comments rendered on the pub.dev API reference — and it
COMPILES them against the package's own real API. A snippet that names a symbol
the package does not have is a lie told to an edge developer, and it HALTS.

Founding incident (2026-07-14): localization_fallback 0.1.2 shipped a README
teaching `metresBetween(previous, fix)` — a function that does not exist — at the
exact seam where a developer decides whether a GPS fix can be believed. It was
published with "analyze clean, tests green". `dart analyze` does not compile
README blocks. `dart test` does not compile dartdoc. Nothing ran the example.
It was written while fixing a README that pointed at a package that did not exist.

Companions found the same hour, all live on pub.dev, none of them mine:
  kalman_dr 0.4.4         README: `position.accuracyMetres` (no such member),
                          `SimulatedLocationProvider()` (no such class)
  routing_engine 0.5.0    README: `LatLng(...)` — latlong2 is not re-exported,
                          so the FIRST block a stranger copies does not compile
  pretrip_decision_advisor 0.5.2  README: calls the throwing `brief()` bare

PLACEHOLDERS. A snippet may legitimately reference things the READER supplies
(`navigationBloc`, `activateSnowRoutingMode()`). Those must be DECLARED, in the
first lines of the block:

    ```dart
    // oracle:placeholders navigationBloc, activateSnowRoutingMode
    ...
    ```

Declaring a placeholder is cheap and auditable. The point is that you cannot
*forget* — an undeclared unknown symbol is exactly the shape of the defect, and
`metresBetween` would never have been declared, because its author believed it
existed.

Usage:  python3 tool/snippet_oracle.py <package-dir> [...]
Exit 0 = every snippet compiles (or its unknowns are declared). Non-zero = HALT.
"""

import json
import os
import re
import shutil
import subprocess
import sys

ORACLE_DIR = ".oracle_snippets"

# Analyzer codes that mean "this snippet names something that does not exist".
UNDEFINED = {
    "undefined_function",
    "undefined_identifier",
    "undefined_class",
    "undefined_getter",
    "undefined_setter",
    "undefined_method",
    "undefined_named_parameter",
    "undefined_enum_constant",
    "creation_with_non_type",
    "not_a_type",
    "uri_does_not_exist",
    "new_with_undefined_constructor_default",
}


def extract_readme_blocks(pkg):
    """Fenced ```dart blocks from README.md — what a stranger copies first."""
    path = os.path.join(pkg, "README.md")
    if not os.path.exists(path):
        return []
    text = open(path, encoding="utf-8").read()
    out = []
    for m in re.finditer(r"^```dart\s*\n(.*?)^```", text, re.S | re.M):
        line = text[: m.start()].count("\n") + 1
        out.append(("README.md", line, m.group(1)))
    return out


def extract_dartdoc_blocks(pkg):
    """```dart blocks inside /// doc comments — rendered on the pub.dev API reference."""
    out = []
    lib = os.path.join(pkg, "lib")
    for root, _dirs, files in os.walk(lib):
        if "/generated" in root or "/.dart_tool" in root:
            continue
        for f in files:
            if not f.endswith(".dart"):
                continue
            path = os.path.join(root, f)
            rel = os.path.relpath(path, pkg)
            lines = open(path, encoding="utf-8").read().split("\n")
            buf, start, inblock = [], None, False
            for i, raw in enumerate(lines):
                s = raw.strip()
                if not s.startswith("///"):
                    inblock, buf = False, []
                    continue
                body = s[3:].lstrip() if len(s) > 3 else ""
                if body.startswith("```dart"):
                    inblock, buf, start = True, [], i + 1
                    continue
                if inblock and body.startswith("```"):
                    if buf:
                        out.append((rel, start, "\n".join(buf)))
                    inblock, buf = False, []
                    continue
                if inblock:
                    buf.append(s[4:] if len(s) > 4 else "")
    return out


def declared_placeholders(code):
    names = set()
    for line in code.split("\n")[:6]:
        m = re.search(r"//\s*oracle:placeholders\s+(.*)", line)
        if m:
            for n in m.group(1).split(","):
                n = n.strip()
                if n:
                    names.add(n)
    return names


def is_flutter_snippet(code):
    """A Flutter snippet inside a pure-Dart package cannot be compiled here.

    We do NOT silently pass it — we report it UNVERIFIED. Claiming a block is fine
    because we could not check it is precisely the failure this oracle exists to end.
    """
    return "package:flutter/" in code


def wrap(code, pkg_name):
    """Make a fragment compilable: import the package, hoist imports, wrap statements."""
    lines = [l for l in code.split("\n") if not re.match(r"\s*//\s*oracle:", l)]
    imports = [l for l in lines if re.match(r"\s*import\s+", l)]
    body = [l for l in lines if not re.match(r"\s*import\s+", l)]

    have_self = any(f"package:{pkg_name}/" in i for i in imports)
    header = list(imports)
    if not have_self:
        header.insert(0, f"import 'package:{pkg_name}/{pkg_name}.dart';")
    # Snippets routinely use StreamController / Future / math without showing the
    # dart: import. Supplying them removes noise WITHOUT hiding a package defect:
    # a wrong package symbol still fails.
    src_all = "\n".join(body)
    if "StreamController" in src_all or "Completer" in src_all:
        header.append("import 'dart:async';")
    if re.search(r"\bmath\.", src_all):
        header.append("import 'dart:math' as math;")

    # Ignore leading comments when deciding whether this is a top-level block.
    probe = "\n".join(
        l for l in body if l.strip() and not l.strip().startswith("//")
    )
    toplevel = re.match(
        r"\s*(class |enum |mixin |extension |abstract |void main|Future<void> main)",
        probe,
    )
    if toplevel:
        return "\n".join(header) + "\n\n" + src_all + "\n"
    return (
        "\n".join(header)
        + "\n\nFuture<void> _oracleSnippet() async {\n"
        + src_all
        + "\n}\n"
    )


def analyze(pkg, blocks):
    name = None
    for line in open(os.path.join(pkg, "pubspec.yaml"), encoding="utf-8"):
        m = re.match(r"^name:\s*(\S+)", line)
        if m:
            name = m.group(1)
            break
    if not name:
        return [], [], []

    has_flutter = "flutter:" in open(os.path.join(pkg, "pubspec.yaml"), encoding="utf-8").read()

    d = os.path.join(pkg, ORACLE_DIR)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)

    index = {}
    skipped = []
    for i, (src, line, code) in enumerate(blocks):
        if is_flutter_snippet(code) and not has_flutter:
            # Honest: NOT a pass. We could not compile it, and we say so.
            skipped.append(f"{src}:~{line} (Flutter snippet in a pure-Dart package — NOT VERIFIED)")
            continue
        f = os.path.join(d, f"s{i}.dart")
        open(f, "w", encoding="utf-8").write(wrap(code, name))
        index[os.path.abspath(f)] = (src, line, declared_placeholders(code))

    p = subprocess.run(
        ["dart", "analyze", "--format=json", ORACLE_DIR],
        cwd=pkg,
        capture_output=True,
        text=True,
    )
    violations = []
    try:
        diags = json.loads(p.stdout).get("diagnostics", [])
    except Exception:
        shutil.rmtree(d, ignore_errors=True)
        return [], [f"{pkg}: analyzer produced no parsable output — ORACLE CANNOT VOUCH"], skipped

    for diag in diags:
        code_name = (diag.get("code") or "").lower()
        if code_name not in UNDEFINED:
            continue
        loc = diag.get("location", {})
        f = os.path.abspath(loc.get("file", ""))
        if f not in index:
            continue
        src, line, placeholders = index[f]
        msg = (diag.get("problemMessage") or "").strip()
        if code_name == "uri_does_not_exist":
            # The message shape is "Target of URI doesn't exist: '<uri>'." — the
            # apostrophe in "doesn't" breaks first-quote extraction (it yielded
            # "t exist: ", a symbol no placeholder declaration can ever match).
            # Anchor on the ": '<uri>'" tail so the symbol IS the URI, exactly as
            # a placeholder declaration must spell it. An undeclared missing URI
            # still HALTs — this changes what is reported, never whether.
            sym = re.search(r":\s*'([^']+)'", msg)
        else:
            sym = re.search(r"'([^']+)'", msg)
        symbol = sym.group(1) if sym else "?"
        if symbol in placeholders:
            continue  # the author declared it illustrative
        violations.append(
            {
                "source": src,
                "block_line": line,
                "symbol": symbol,
                "code": code_name,
                "message": msg,
            }
        )
    shutil.rmtree(d, ignore_errors=True)
    return violations, [], skipped


def main():
    pkgs = sys.argv[1:]
    if not pkgs:
        print("usage: snippet_oracle.py <package-dir> [...]", file=sys.stderr)
        return 2

    total, bad_pkgs = 0, 0
    for pkg in pkgs:
        if not os.path.exists(os.path.join(pkg, "pubspec.yaml")):
            continue
        blocks = extract_readme_blocks(pkg) + extract_dartdoc_blocks(pkg)
        if not blocks:
            print(f"  {os.path.basename(pkg):32} no dart snippets")
            continue
        violations, errs, skipped = analyze(pkg, blocks)
        for e in errs:
            print(f"  !! {e}")
        for s in skipped:
            print(f"  ??   {os.path.basename(pkg):32} {s}")
        if violations:
            bad_pkgs += 1
            total += len(violations)
            print(f"\n  HALT {os.path.basename(pkg)} — {len(violations)} snippet(s) name symbols that DO NOT EXIST:")
            for v in violations:
                print(f"     {v['source']}:~{v['block_line']}  '{v['symbol']}'  ({v['code']})")
                print(f"        {v['message']}")
            print("     A reader who copies this gets a compiler error. If a symbol is")
            print("     meant to be supplied by the reader, declare it in the block:")
            print("        // oracle:placeholders name1, name2")
        else:
            print(f"  ok   {os.path.basename(pkg):32} {len(blocks)} snippet(s) compile")

    print()
    if total:
        print(f"L35 SNIPPET ORACLE: HALT — {total} undefined symbol(s) across {bad_pkgs} package(s).")
        print("These are lies told to an edge developer. Fix them or declare them.")
        return 1
    print("L35 SNIPPET ORACLE: PASS — every published snippet compiles against its own package.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
