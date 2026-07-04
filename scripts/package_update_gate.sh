#!/usr/bin/env bash
# package_update_gate.sh — the DETERMINISTIC gates of the multi-gate package-update method.
#
# A package update is never "tested" by a single pass (OPS-RULE-068). The full method has
# five gates; this script runs the mechanically-checkable ones so every update candidate —
# these and every FUTURE one — passes the same battery before a republish is even proposed:
#
#   G1  build+resolve     dart pub get          (does it still resolve?)
#   G2  static analysis   dart analyze          (lint clean?)
#   G3  tests             dart test             (suite green?)
#   G4  publish-ready     dart pub publish -n   (0 pub.dev warnings?)
#   G5  coherence         catalog_census.sh     (after publish: live==committed==local?)
#   G6  provenance        lib-delta vs pub.dev  (BEFORE publish: does a "no-code/docs-only"
#                                                CHANGELOG claim contradict an EXECUTABLE
#                                                lib delta vs the latest published archive?)
#   G7  hosted-resolve    strip overrides +     (does the package's DECLARED hosted sibling
#                         dart/flutter pub get   constraint actually resolve + pass tests for a
#                         + test (in a copy)     clean `pub add` consumer — not just locally?)
#
# G6 closes the failure learned 2026-06-30: snow_rendering 0.2.4 ("no API change") and
# kalman_dr 0.4.3 ("No code change") were published while their lib/ actually differed
# from the prior published version by executable/API changes (a new enum, an export, a new
# field). A false change-class reached IMMUTABLE pub.dev. G5 only checks live==committed==
# local AFTER publish; it never compares a "docs-only" CHANGELOG against the real lib delta
# vs the prior published archive. G6 does — it downloads the latest published archive, diffs
# its lib/ against the working-tree lib/, and FAILS when a no-code/docs-only changelog claim
# rides an executable delta. The honest-declaration suppressor is negation-aware (DIA cert
# 2026-06-30, GAP-1 closed): only a STRUCTURAL bullet/conventional-commit prefix (`- fix:`,
# `feat(...)`, `BREAKING:`) or a POSITIVE non-negated "breaking"/"<code|api|source|behaviour>
# change" declaration suppresses the check — incidental/negated prose ("(does not fix ...)",
# "non-breaking") no longer disarms it, and an honest correction entry that QUOTES a prior
# "no api change" mislabel still passes because it positively declares the change.
# Honest scope (what G6 does NOT do): it does not judge whether a DECLARED change is correctly
# described — only the no-code-claim-vs-executable-delta contradiction. Known gaps: code
# moved/reordered with byte-identical lines nets to zero (within-file reorder can be missed;
# cross-file moves are caught); block-comment-only (/* */) edits are treated conservatively as
# executable (over-strict, safe direction); a CHANGELOG with no `## ` version heading WARNs
# rather than FAILs (GAP-4 — change-class unverifiable, not silently passed); requires network
# (pub.dev unreachable yields SKIP, so G6 is not a substitute for the always-local G5). See
# provenance_gate().
#
# G7 closes the resolution-masking failure (the OTHER half of the monorepo-override hazard that
# G6 does not reach). Six published packages ship monorepo-only `dependency_overrides: path:` on
# their siblings (navigation_safety, routing_bloc, adaptive_reroute, driving_weather,
# voice_guidance, driving_conditions). Neither CI (.github/workflows/ci.yml — every job runs
# `pub get` HONORING those overrides) nor G1 (which also honors overrides) ever resolves a
# package's DECLARED HOSTED sibling constraints against pub.dev. So they certify "works on my
# local checkout," never "works for an edge developer who `pub add`s it." G7 reproduces the clean
# consumer: it copies the package to a temp dir, DELETES only the `dependency_overrides:` block,
# runs `dart`/`flutter pub get` (now resolving the declared caret constraints from pub.dev, NOT
# local path), and — if that resolves — runs the package's own tests against the HOSTED siblings.
#   VERDICT  PASS  pub-get resolves hosted AND tests pass (a clean `pub add` works).
#            FAIL  declared hosted constraint will NOT resolve against published versions, OR
#                  it resolves but tests FAIL against the published siblings (overrides masked it).
#            SKIP  pub.dev unreachable (mirror G6 SKIP_NET — NEVER block offline); OR the package
#                  has no `dependency_overrides` (nothing to strip — G1's normal resolve already
#                  covered its hosted deps); OR a sibling version the declared constraint needs is
#                  not published yet but the LOCAL sibling satisfies it (a coordinated multi-package
#                  release in flight — prints which sibling/version). Honest scope: G7 needs the
#                  sibling already published and needs the network (else SKIP); it is NOT a
#                  substitute for G6 (change-class honesty) or the always-local G1/G5. See
#                  hosted_resolve_gate().
#
# The JUDGMENT gate — adversarial verify, advocate!=verifier (OPS-068 §B) — is conducted by
# the `multi-gate-package-update` workflow, NOT this script (free-text judgment is not
# mechanically gateable; claiming it is would be the narration-over-reading failure, OPS-062).
# The REPUBLISH gate is the Chair's voice (§1). This script reads only; it never publishes,
# commits, or pushes.
#
# Usage:
#   ./scripts/package_update_gate.sh <pkg> [<pkg> ...]     # gate the named update candidates
#   ./scripts/package_update_gate.sh --coherence-only      # just the catalog-wide G5
#   ./scripts/package_update_gate.sh --provenance-sweep    # G6 across the WHOLE catalog
#   ./scripts/package_update_gate.sh --g7 <pkg> [<pkg>...]  # ONLY the G7 hosted-resolve gate
#   ./scripts/package_update_gate.sh --hosted-resolve-sweep # G7 across all override-bearing pkgs
#   PKG_ROOT=/path ./scripts/package_update_gate.sh <pkg>
#   G6_COMPARE_VERSION=0.2.3 ./scripts/package_update_gate.sh <pkg>   # pin G6's compare version
#
# Exit 0 only if every gate passed for every named package (and coherence is clean).

set -u
PKG_ROOT="${PKG_ROOT:-/home/komada/SNGNav/packages}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

fail=0
gate() { # gate <label> <cmd...> ; prints PASS/FAIL, sets fail on error
  local label="$1"; shift
  if "$@" >/tmp/_pkg_gate_out 2>&1; then
    printf '    %-14s PASS\n' "$label"
  else
    printf '    %-14s FAIL\n' "$label"; fail=1
    sed 's/^/        /' /tmp/_pkg_gate_out | tail -6
  fi
}

# G4 publish-readiness, staging-aware: a STAGED update has uncommitted package files,
# so pub's "N checked-in files are modified in git" warning is EXPECTED (not a defect).
# PASS = 0 warnings; STAGED = the only warning is the git-modified one; FAIL = any real
# content warning (missing example, bad pubspec, oversized, etc.).
dryrun_gate() { # dryrun_gate <pkgdir>
  local out; out="$(cd "$1" && dart pub publish --dry-run 2>&1)"
  if echo "$out" | grep -qiE "Package has 0 warnings"; then
    printf '    %-14s PASS\n' "G4 dry-run"
  elif echo "$out" | grep -qiE "checked-in files are modified in git"; then
    local nw; nw="$(echo "$out" | grep -oiE "Package has [0-9]+ warning" | grep -oE '[0-9]+')"
    if [[ "${nw:-1}" -le 1 ]]; then
      local nf; nf="$(echo "$out" | grep -oE "[0-9]+ checked-in files are modified" | grep -oE '^[0-9]+')"
      printf '    %-14s STAGED (%s files modified; publish-ready once committed)\n' "G4 dry-run" "${nf:-?}"
    else
      printf '    %-14s FAIL (real warning beyond git-modified)\n' "G4 dry-run"; echo "$out" | grep -iE "warning|missing|error" | sed 's/^/        /' | head -5; fail=1
    fi
  else
    printf '    %-14s FAIL\n' "G4 dry-run"; echo "$out" | grep -iE "warning|missing|error" | sed 's/^/        /' | head -5; fail=1
  fi
}

# G5 coherence, staging-aware: a LOCAL-AHEAD on a package UNDER TEST (its staged version
# bump) is EXPECTED and reported STAGED; any DRIFT, or LOCAL-AHEAD on a package NOT under
# test, is a real FAIL. Pass the tested package names as args; none = strict mode.
coherence() {
  echo ">> G5 coherence (live == committed == local; staged updates expected-ahead)"
  bash "$HERE/catalog_census.sh" coherence >/tmp/_coh 2>&1
  local bad=0 staged=0
  while IFS= read -r line; do
    local pname; pname="$(echo "$line" | awk '{print $1}')"
    if echo "$line" | grep -q "LOCAL-AHEAD" && ! echo "$line" | grep -q "DRIFT"; then
      if [[ " $* " == *" $pname "* ]]; then echo "    $pname  STAGED (expected-ahead — under test)"; staged=1; else echo "    $pname  FAIL (LOCAL-AHEAD, not under test)"; bad=1; fi
    else
      echo "    $pname  FAIL"; bad=1
    fi
  done < <(grep -E "DRIFT|LOCAL-AHEAD" /tmp/_coh)
  if [[ "$bad" -eq 1 ]]; then fail=1
  elif [[ "$staged" -eq 1 ]]; then echo "    coherence     STAGED — only expected-ahead drift on packages under test"
  else echo "    coherence     PASS — every publishable package coherent"; fi
}

# ---------------------------------------------------------------------------
# G6 provenance — release-provenance gate (Andon recurrence-prevention loom).
#
# Per package: fetch the CURRENT latest published version + archive_url from pub.dev,
# download+extract that archive's lib/, `diff -ruN` it against the working-tree lib/,
# read the CHANGELOG.md TOP entry, and FAIL when the top entry claims a no-code/docs-only
# change-class BUT the lib delta is EXECUTABLE (a real code/API/export change the next
# publish would ship). PASS when the changelog honestly declares a code change, OR the lib
# delta is doc-only/empty. SKIP when the package is unpublished or pub.dev is unreachable.
#
# G6_COMPARE_VERSION pins the published version to compare against (used for self-test and
# to reproduce a moment-of-publish condition, e.g. compare current source against the
# version that was "latest" at the instant the mislabeled release went out).
# ---------------------------------------------------------------------------
G6_TMP="$(mktemp -d "${TMPDIR:-/tmp}/g6.XXXXXX")"
G7_TMP="$(mktemp -d "${TMPDIR:-/tmp}/g7.XXXXXX")"   # G7 working area; cleaned by the same EXIT trap
trap 'rm -rf "$G6_TMP" "$G7_TMP"' EXIT
G6_VERPARSE="$G6_TMP/verparse.py"
G6_CLASSIFY="$G6_TMP/classify.py"
G7_STRIP="$G7_TMP/strip_overrides.py"       # removes ONLY the top-level dependency_overrides block
G7_CLASSIFY="$G7_TMP/classify_sibling.py"   # per-sibling: declared constraint vs published vs local

cat > "$G6_VERPARSE" <<'PYVER'
import sys, json, os
want = os.environ.get('G6_CMP', '')
try:
    d = json.load(sys.stdin)
except Exception:
    print('(unpub) -'); sys.exit(0)
if not isinstance(d, dict) or 'latest' not in d:
    print('(unpub) -'); sys.exit(0)
if want:
    u = ''
    for v in d.get('versions', []):
        if v.get('version') == want:
            u = v.get('archive_url', '') or ''
            break
    print(want, u if u else '-')
else:
    lat = d.get('latest', {})
    print(lat.get('version', '(unpub)'), lat.get('archive_url', '-'))
PYVER

cat > "$G6_CLASSIFY" <<'PYCLS'
import sys, re
changelog_path = sys.argv[1] if len(sys.argv) > 1 else ''
diff_path      = sys.argv[2] if len(sys.argv) > 2 else ''

# ---- CHANGELOG top-entry no-code-claim detection ----
def top_entry(text):
    lines = text.splitlines()
    start = None
    for i, l in enumerate(lines):
        if re.match(r'^\s{0,3}##\s+', l):
            start = i; break
    if start is None:
        return ''
    out = [lines[start]]
    for l in lines[start + 1:]:
        if re.match(r'^\s{0,3}##\s+', l):
            break
        out.append(l)
    return '\n'.join(out)

try:
    cl = open(changelog_path, encoding='utf-8', errors='replace').read()
except Exception:
    cl = ''
entry = top_entry(cl)
el = entry.lower()

NO_CODE = ["no api change", "no code change", "no source change",
           "no behavior change", "no behaviour change",
           "docs:", "docs only", "doc-only", "documentation only"]
has_nocode = any(p in el for p in NO_CODE)

# An ACCOMPANYING honest code/feat/fix/BREAKING declaration suppresses the contradiction.
# GAP-1 fix (DIA cert 2026-06-30): the honest signal must be STRUCTURAL (a changelog-bullet /
# conventional-commit prefix at line start) or a POSITIVE declaration — never an incidental or
# NEGATED word in prose. So "(does not fix ...)" and "non-breaking" must NOT disarm the no-code
# check, while "a breaking change" / "- fix: ..." still do. This also lets an honest correction
# entry that QUOTES a prior "no api change" mislabel pass, because it positively declares the
# change it is documenting. A negation immediately before the token voids it.
honest = False
# The honest-declaration suppressor is STRUCTURAL ONLY (DIA re-cert 2026-06-30, GAP-1 final):
# free prose cannot disarm the no-code claim — incidental "breaking news" / "api change
# request" must NOT pass, and negated "non-breaking" / "(does not fix)" must NOT pass. A real
# code change is declared with a conventional-commit / changelog-bullet marker, an explicit
# BREAKING-change marker, or a bold **breaking ...** callout. (This is intentionally strict:
# it over-flags an honest PROSE-only change — the author then adds a structural marker —
# rather than ever under-flag a mislabel. An honest correction that QUOTES a prior "no api
# change" still passes when it carries one of these markers, as the 0.2.5 corrective does.)
# (1) conventional-commit / changelog-bullet honest type at LINE START:
if re.search(r'(?m)^\s*[-*]?\s*(feat|fix|feature|perf|refactor)\s*(\(|:|!)', el):
    honest = True
# (2) an explicit BREAKING-change marker (CC footer/heading "breaking change" / "breaking:"):
if re.search(r'(?m)^\s*[-*>\s]*breaking([ -]?change|\s*[:!])', el):
    honest = True
# (3) a bold **breaking ...** emphasis (a deliberate breaking-change callout in prose):
if re.search(r'\*\*\s*breaking', el):
    honest = True

claims_no_code = has_nocode and not honest

# ---- lib delta executable-vs-doc-only classification ----
# code_sig(line): the line with any //-or-///-comment stripped (respecting string/char
# literals so `https://` is not mistaken for a comment) and whitespace trimmed. A pure
# comment line or blank line -> empty signature -> ignored.
def code_sig(line):
    res = []; i = 0; n = len(line); q = None
    while i < n:
        c = line[i]
        if q:
            res.append(c)
            if c == '\\' and i + 1 < n:
                res.append(line[i + 1]); i += 2; continue
            if c == q:
                q = None
            i += 1; continue
        if c in ("'", '"'):
            q = c; res.append(c); i += 1; continue
        if c == '/' and i + 1 < n and line[i + 1] == '/':
            break                     # // or /// line comment begins
        res.append(c); i += 1
    return ''.join(res).strip()

try:
    diff = open(diff_path, encoding='utf-8', errors='replace').read()
except Exception:
    diff = ''

cur = '?'
files = {}   # path -> [added{sig:count}, removed{sig:count}]
def slot(f):
    files.setdefault(f, [dict(), dict()]); return files[f]

for raw in diff.splitlines():
    if raw.startswith('+++ '):
        p = raw[4:].split('\t')[0].strip()
        if p != '/dev/null':
            cur = p
        continue
    if raw.startswith('--- '):
        p = raw[4:].split('\t')[0].strip()
        if cur == '?' and p != '/dev/null':
            cur = p
        continue
    if raw.startswith('@@') or raw.startswith('diff ') or raw.startswith('index '):
        continue
    if raw.startswith('Binary '):
        m = re.search(r'Binary files (.+?) and (.+?) differ', raw)
        f = m.group(2) if m else 'binary'
        a = slot(f)[0]; a['<binary>'] = a.get('<binary>', 0) + 1
        continue
    if not raw:
        continue
    if raw[0] == '+':
        s = code_sig(raw[1:])
        if s:
            a = slot(cur)[0]; a[s] = a.get(s, 0) + 1
    elif raw[0] == '-':
        s = code_sig(raw[1:])
        if s:
            r = slot(cur)[1]; r[s] = r.get(s, 0) + 1

net_total = 0
exec_files = []
sample = []
for f, (a, r) in files.items():
    fnet = 0; fsamp = []
    for k in set(a) | set(r):
        d = a.get(k, 0) - r.get(k, 0)
        if d != 0:
            fnet += abs(d)
            fsamp.append(('+' if d > 0 else '-', k))
    if fnet > 0:
        exec_files.append((f, fnet)); net_total += fnet
        for sgn, k in fsamp[:8]:
            sample.append((f, sgn, k))

executable = net_total > 0
print("CLAIM=%d" % (1 if claims_no_code else 0))
print("DELTA=%s" % ('executable' if executable else 'doconly'))
print("NETCOUNT=%d" % net_total)
# GAP-4 (DIA cert 2026-06-30): a CHANGELOG with no `## ` version heading yields no detectable
# claim, so a mislabel could pass silently. Flag the no-heading case so the gate WARNs (not a
# silent PASS) when there is also an executable delta to ship.
print("NOHEADING=%d" % (1 if not entry.strip() else 0))
fl = ''
for l in entry.splitlines():
    if l.strip():
        fl = l.strip(); break
print("ENTRY=%s" % fl)
for f, c in exec_files[:20]:
    idx = f.find('/lib/')
    print("FILE\t%s\t%d" % (f[idx + 1:] if idx >= 0 else f, c))
for f, sgn, k in sample[:24]:
    print("NETLINE\t%s\t%s" % (sgn, k[:120]))
PYCLS

# G7 strip helper — remove ONLY the top-level `dependency_overrides:` block from a pubspec copy.
# The block is the key at column 0 plus every following blank/indented line, up to the next
# column-0 line (a new top-level key/comment) or EOF. Nothing else is touched.
cat > "$G7_STRIP" <<'PYSTRIP'
import sys, re
path = sys.argv[1]
with open(path, encoding='utf-8', errors='replace') as f:
    lines = f.readlines()
out = []; i = 0; n = len(lines); removed = 0
while i < n:
    line = lines[i]
    if re.match(r'^dependency_overrides:[ \t]*(#.*)?\r?\n?$', line):
        removed += 1; i += 1
        while i < n:                       # consume the block body
            b = lines[i]
            if b.strip() == '' or b[:1] in (' ', '\t'):
                i += 1; continue           # blank or indented => still inside the block
            break                          # column-0 non-blank => block ended
        continue
    out.append(line); i += 1
with open(path, 'w', encoding='utf-8') as f:
    f.writelines(out)
sys.stderr.write('g7-strip: removed %d dependency_overrides block(s)\n' % removed)
PYSTRIP

# G7 sibling classifier — given the package pubspec, an overridden sibling name, and the local
# sibling pubspec path (or '-'), plus the sibling's pub.dev API JSON on stdin, decide:
#   HOSTED_SAT  does ANY published (stable) sibling version satisfy the package's DECLARED caret
#               constraint?  (Dart caret: ^1.2.3 -> >=1.2.3 <2.0.0 ; ^0.10.0 -> >=0.10.0 <0.11.0 ;
#               ^0.0.5 -> >=0.0.5 <0.0.6 — the leftmost-non-zero rule, implemented exactly.)
#   LOCAL_SAT   does the LOCAL monorepo sibling version satisfy that same constraint?
# A SKIP-not-yet-published case is HOSTED_SAT=0 AND LOCAL_SAT=1 (coordinated release in flight).
cat > "$G7_CLASSIFY" <<'PYSIB'
import sys, json, re
pkg_pubspec   = sys.argv[1]
name          = sys.argv[2]
local_pubspec = sys.argv[3] if len(sys.argv) > 3 else '-'

def read(p):
    try: return open(p, encoding='utf-8', errors='replace').read()
    except Exception: return ''

def declared_constraint(text, dep):
    in_deps = False
    for l in text.splitlines():
        if re.match(r'^dependencies:\s*$', l):
            in_deps = True; continue
        if in_deps:
            if re.match(r'^\S', l):          # next top-level key ends the dependencies block
                break
            m = re.match(r'^\s+([A-Za-z0-9_]+):\s*(.*)$', l)
            if m and m.group(1) == dep:
                return m.group(2).strip()
    return ''

def parse_core(s):
    core = s.strip().split('+')[0]
    if '-' in core: core = core.split('-', 1)[0]
    nums = []
    for x in re.split(r'\.', core)[:3]:
        try: nums.append(int(re.match(r'\d+', x).group()))
        except Exception: nums.append(0)
    while len(nums) < 3: nums.append(0)
    return tuple(nums[:3])

def is_pre(v): return '-' in v.split('+')[0]
INF = (10**9, 0, 0)

def clauses_for(c):
    c = c.strip()
    if (c[:1], c[-1:]) in (('"', '"'), ("'", "'")): c = c[1:-1].strip()
    if c == '' or c == 'any':
        return [('>=', (0, 0, 0)), ('<', INF)]
    if c.startswith('^'):
        maj, minr, pat = parse_core(c[1:])
        if maj > 0:   high = (maj + 1, 0, 0)
        elif minr > 0: high = (maj, minr + 1, 0)
        else:          high = (maj, minr, pat + 1)
        return [('>=', (maj, minr, pat)), ('<', high)]
    toks = c.split(); cl = []
    for t in toks:
        m = re.match(r'^(>=|<=|>|<|=)?\s*([0-9][\w.\-+]*)$', t)
        if not m: continue
        op = m.group(1) or '=='
        if op == '=': op = '=='
        cl.append((op, parse_core(m.group(2))))
    if cl: return cl
    if re.match(r'^[0-9]', c): return [('==', parse_core(c))]
    return [('>=', (0, 0, 0)), ('<', INF)]

def satisfies(v, clauses):
    for op, ref in clauses:
        if op == '>=' and not (v >= ref): return False
        if op == '>'  and not (v >  ref): return False
        if op == '<=' and not (v <= ref): return False
        if op == '<'  and not (v <  ref): return False
        if op == '==' and not (v == ref): return False
    return True

constraint = declared_constraint(read(pkg_pubspec), name)
clauses = clauses_for(constraint)
try:
    d = json.load(sys.stdin)
    versions = [x['version'] for x in d.get('versions', []) if 'version' in x]
    latest = d.get('latest', {}).get('version', '')
except Exception:
    versions = []; latest = ''
stable = [v for v in versions if not is_pre(v)]
hosted_sat = any(satisfies(parse_core(v), clauses) for v in stable)
local_v = ''
m = re.search(r'(?m)^version:\s*(\S+)', read(local_pubspec)) if local_pubspec != '-' else None
if m: local_v = m.group(1)
local_sat = bool(local_v) and satisfies(parse_core(local_v), clauses)
print('CONSTRAINT=%s' % (constraint if constraint else '-'))
print('HOSTED_SAT=%d' % (1 if hosted_sat else 0))
print('LOCAL_SAT=%d'  % (1 if local_sat else 0))
print('LOCAL_VER=%s'  % (local_v if local_v else '-'))
print('LATEST_PUB=%s' % (latest if latest else '-'))
PYSIB

# g6_compute <pkgdir> <name> -> echoes "STATUS|VER|CLAIM|DELTA|NETCOUNT"
# Full per-package detail (ENTRY/FILE/NETLINE lines) is left in $G6_TMP/last_out.
# STATUS: OK | SKIP_UNPUB | SKIP_NET | SKIP_NOLIB | SKIP_NOVER
g6_compute() {
  local pkg="$1" name="$2"
  : > "$G6_TMP/last_out"
  [[ -d "$pkg/lib" ]] || { echo "SKIP_NOLIB||||"; return; }
  command -v curl >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1 || { echo "SKIP_NET||||"; return; }
  local api; api="$(curl -s --max-time 25 "https://pub.dev/api/packages/$name" 2>/dev/null)"
  [[ -n "$api" ]] || { echo "SKIP_NET||||"; return; }
  local ver url
  read -r ver url < <(printf '%s' "$api" | G6_CMP="${G6_COMPARE_VERSION:-}" python3 "$G6_VERPARSE")
  [[ "$ver" == "(unpub)" ]] && { echo "SKIP_UNPUB||||"; return; }
  [[ -n "$url" && "$url" != "-" ]] || { echo "SKIP_NOVER|$ver|||"; return; }
  local tgz="$G6_TMP/a.tgz" exdir="$G6_TMP/ex"
  rm -rf "$exdir" "$tgz"; mkdir -p "$exdir"
  curl -sL --max-time 60 "$url" -o "$tgz" 2>/dev/null
  if [[ ! -s "$tgz" ]] || ! tar xzf "$tgz" -C "$exdir" 2>/dev/null; then echo "SKIP_NET|$ver|||"; return; fi
  [[ -d "$exdir/lib" ]] || mkdir -p "$exdir/lib"
  diff -ruN "$exdir/lib" "$pkg/lib" > "$G6_TMP/diff.txt" 2>/dev/null
  python3 "$G6_CLASSIFY" "$pkg/CHANGELOG.md" "$G6_TMP/diff.txt" > "$G6_TMP/last_out" 2>/dev/null
  local claim delta net
  claim="$(sed -n 's/^CLAIM=//p' "$G6_TMP/last_out")"
  delta="$(sed -n 's/^DELTA=//p' "$G6_TMP/last_out")"
  net="$(sed -n 's/^NETCOUNT=//p' "$G6_TMP/last_out")"
  echo "OK|$ver|${claim:-0}|${delta:-doconly}|${net:-0}"
}

# provenance_gate <pkgdir> <name> — the per-package G6 gate; sets fail=1 on a real
# contradiction (no-code claim + executable delta) when there IS a pending bump.
provenance_gate() {
  local pkg="$1" name="$2"
  local rec; rec="$(g6_compute "$pkg" "$name")"
  local status ver claim delta net
  IFS='|' read -r status ver claim delta net <<<"$rec"
  case "$status" in
    SKIP_NOLIB) printf '    %-14s SKIP (no lib/ dir)\n'                                   "G6 provenance"; return;;
    SKIP_UNPUB) printf '    %-14s SKIP (unpublished — nothing to compare)\n'              "G6 provenance"; return;;
    SKIP_NET)   printf '    %-14s SKIP (pub.dev unreachable / archive fetch failed)\n'    "G6 provenance"; return;;
    SKIP_NOVER) printf '    %-14s SKIP (compare version %s not on pub.dev)\n' "G6 provenance" "$ver"; return;;
  esac
  local srcver entry noheading info=""
  srcver="$(grep -m1 '^version:' "$pkg/pubspec.yaml" | awk '{print $2}')"
  entry="$(sed -n 's/^ENTRY=//p' "$G6_TMP/last_out")"
  noheading="$(sed -n 's/^NOHEADING=//p' "$G6_TMP/last_out")"
  [[ "$srcver" == "$ver" ]] && info=" [informational: no pending bump; src==published $ver]"
  if [[ "$claim" == "1" && "$delta" == "executable" ]]; then
    if [[ -n "$info" ]]; then
      # src == compared published version: this is a live/local lib drift (G5's domain),
      # not a pending-publish mislabel. Report, but do not block — there is nothing to publish.
      printf '    %-14s INFO (no pending bump, but lib differs from published %s while CHANGELOG claims no-code — see G5 coherence)\n' "G6 provenance" "$ver"
      printf '        changelog top: %s\n' "$entry"
    else
      printf '    %-14s FAIL (CHANGELOG top claims no-code/docs-only, but lib delta vs published %s is EXECUTABLE — %s net code line(s))\n' "G6 provenance" "$ver" "$net"
      printf '        changelog top: %s\n' "$entry"
      sed -n 's/^FILE\t/        exec-changed file: /p' "$G6_TMP/last_out" | sed 's/\t/   (+\/- /; s/$/ net line(s))/' | head -8
      echo "        executable hunks (sample):"
      sed -n 's/^NETLINE\t\(.\)\t/          \1 /p' "$G6_TMP/last_out" | head -12
      fail=1
    fi
  else
    if [[ "$delta" == "executable" && "$noheading" == "1" ]]; then
      # GAP-4: executable delta but the CHANGELOG has no `## ` version heading, so no claim
      # could be detected. Do not block (a missing heading is not itself a mislabel), but WARN
      # loudly rather than silently PASS — the change-class is unverifiable from this changelog.
      printf '    %-14s WARN (lib delta vs published %s is EXECUTABLE but CHANGELOG.md has no `## ` version entry — change-class unverifiable; add a versioned entry)%s\n' "G6 provenance" "$ver" "$info"
    elif [[ "$delta" == "executable" ]]; then
      printf '    %-14s PASS (lib delta vs published %s is executable AND honestly declared in CHANGELOG)%s\n' "G6 provenance" "$ver" "$info"
    else
      printf '    %-14s PASS (lib delta vs published %s is doc-only/empty; CHANGELOG claim consistent)%s\n'   "G6 provenance" "$ver" "$info"
    fi
  fi
}

# provenance_sweep — G6's lib-vs-latest-published executable-delta check across ALL packages.
# Reports, per package, whether the current source lib has executable changes AHEAD of the
# latest published version, and flags the dangerous combo (exec-ahead + no-code changelog
# claim) so a future bump cannot silently mislabel them. For the retroactive catalog sweep.
provenance_sweep() {
  echo ">> G6 provenance sweep — current source lib vs LATEST published, per package"
  echo "   EXEC-AHEAD(n) = next publish would ship n net executable line(s); in-sync = no executable delta."
  echo "   FLAG '!! no-code-claim' = EXEC-AHEAD *and* the CHANGELOG top still claims a no-code/docs-only class."
  printf '%-42s %-10s %-10s %-14s %s\n' "PACKAGE" "PUBLISHED" "SRC" "DELTA" "FLAG"
  printf '%.0s-' {1..96}; echo
  local warned=0 name srcver rec status ver claim delta net dcol flag
  for pkg in "$PKG_ROOT"/*/; do
    pkg="${pkg%/}"; name="$(basename "$pkg")"
    [[ -f "$pkg/pubspec.yaml" ]] || continue
    srcver="$(grep -m1 '^version:' "$pkg/pubspec.yaml" | awk '{print $2}')"
    rec="$(G6_COMPARE_VERSION='' g6_compute "$pkg" "$name")"   # sweep always compares vs LATEST
    IFS='|' read -r status ver claim delta net <<<"$rec"
    flag=""
    case "$status" in
      OK)
        if [[ "$delta" == "executable" ]]; then dcol="EXEC-AHEAD($net)"; else dcol="in-sync"; fi
        if [[ "$delta" == "executable" && "$claim" == "1" ]]; then flag="!! no-code-claim"; warned=1; fi
        ;;
      SKIP_UNPUB) ver="(unpub)"; dcol="-";;
      SKIP_NET)   ver="${ver:-?}"; dcol="(net-skip)";;
      SKIP_NOLIB) ver="${ver:-?}"; dcol="(no lib)";;
      SKIP_NOVER) dcol="(no ver)";;
      *)          dcol="(skip)";;
    esac
    printf '%-42s %-10s %-10s %-14s %s\n' "$name" "${ver:-?}" "$srcver" "$dcol" "$flag"
  done
  echo
  if [[ "$warned" -eq 1 ]]; then
    echo "!! RISK: a package has EXECUTABLE source changes ahead of its published version WHILE its"
    echo "   CHANGELOG top still claims a no-code/docs-only class. A future bump would ship a mislabeled"
    echo "   release (the 2026-06-30 snow_rendering 0.2.4 / kalman_dr 0.4.3 failure). Fix the CHANGELOG first."
    return 1
  fi
  echo "OK: every EXEC-AHEAD package honestly declares a code change in its CHANGELOG top entry (no mislabel risk)."
  return 0
}

# ---------------------------------------------------------------------------
# G7 hosted-resolve — the resolution-masking gate (the OTHER half of the monorepo-override hazard).
#
# Per override-bearing package: copy it to a temp dir, DELETE only the `dependency_overrides:`
# block, then `dart`/`flutter pub get` (resolving the DECLARED hosted sibling constraints from
# pub.dev, NOT local path) and — if that resolves — run the package's own tests against those
# HOSTED siblings. This reproduces exactly what `pub add <pkg>` gives a clean consumer, the
# guarantee CI and G1 never check because they honor the overrides.
# Sets fail=1 on a real FAIL. SKIP paths never set fail (never block offline / on nothing-to-strip).
# ---------------------------------------------------------------------------

# g7_siblings <pubspec> — list the override KEYS (the sibling names) at the block's base indent.
g7_siblings() {
  awk '
    /^dependency_overrides:/{ind=1; base=-1; next}
    ind && /^[^[:space:]]/{ind=0}
    ind {
      if (match($0, /^[[:space:]]+/)) {
        cur=RLENGTH
        if ($0 ~ /^[[:space:]]+[A-Za-z0-9_]+:/) {
          if (base==-1) base=cur
          if (cur==base) { line=$0; sub(/^[[:space:]]+/,"",line); sub(/:.*/,"",line); print line }
        }
      }
    }' "$1"
}

hosted_resolve_gate() {
  local pkg="$1" name="$2" label="G7 hosted-resolve"

  # SKIP: nothing to strip — G1's normal resolve already exercised this package's hosted deps.
  if ! grep -qE '^dependency_overrides:' "$pkg/pubspec.yaml" 2>/dev/null; then
    printf '    %-14s SKIP (no dependency_overrides — G1 normal resolve already covers hosted deps)\n' "$label"
    return
  fi

  # SKIP (offline, mirror G6 SKIP_NET): never block when pub.dev is unreachable.
  command -v curl >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1 \
    || { printf '    %-14s SKIP (curl/python3 unavailable — cannot reach pub.dev)\n' "$label"; return; }
  if ! curl -s --max-time 15 -o /dev/null "https://pub.dev/api/packages/$name" 2>/dev/null \
     && ! curl -s --max-time 15 -o /dev/null "https://pub.dev" 2>/dev/null; then
    printf '    %-14s SKIP (pub.dev unreachable — never block offline)\n' "$label"
    return
  fi

  # Pre-check each overridden sibling: if the DECLARED constraint has no satisfying PUBLISHED
  # version but the LOCAL sibling satisfies it, this is a coordinated release in flight -> SKIP
  # (print which). If neither hosted nor local satisfies, fall through so the real pub-get error
  # surfaces as the FAIL the gate is built to catch.
  local sib api rec cons hsat lsat lver lpub
  while IFS= read -r sib; do
    [[ -n "$sib" ]] || continue
    api="$(curl -s --max-time 25 "https://pub.dev/api/packages/$sib" 2>/dev/null)"
    if [[ -z "$api" ]]; then
      printf '    %-14s SKIP (pub.dev metadata for sibling %s unavailable — never block offline)\n' "$label" "$sib"
      return
    fi
    rec="$(printf '%s' "$api" | python3 "$G7_CLASSIFY" "$pkg/pubspec.yaml" "$sib" "$PKG_ROOT/$sib/pubspec.yaml" 2>/dev/null)"
    cons="$(sed -n 's/^CONSTRAINT=//p' <<<"$rec")"
    hsat="$(sed -n 's/^HOSTED_SAT=//p'  <<<"$rec")"
    lsat="$(sed -n 's/^LOCAL_SAT=//p'   <<<"$rec")"
    lver="$(sed -n 's/^LOCAL_VER=//p'   <<<"$rec")"
    lpub="$(sed -n 's/^LATEST_PUB=//p'  <<<"$rec")"
    if [[ "$hsat" != "1" && "$lsat" == "1" ]]; then
      printf '    %-14s SKIP (sibling %s constraint %s satisfied by LOCAL %s but NOT yet on pub.dev; latest published %s — coordinated release in flight)\n' \
        "$label" "$sib" "$cons" "$lver" "$lpub"
      return
    fi
  done < <(g7_siblings "$pkg/pubspec.yaml")

  # Build the clean-consumer copy: strip ONLY the override block; force a fresh resolve.
  local work; work="$(mktemp -d "$G7_TMP/${name}.XXXXXX")"
  cp -a "$pkg/." "$work/" 2>/dev/null
  rm -rf "$work/.dart_tool" "$work/build" "$work/pubspec.lock" "$work/.packages" \
         "$work/.flutter-plugins" "$work/.flutter-plugins-dependencies"
  # A bundled example/ app carries monorepo-only `path:`/override sibling deps and (for flutter
  # packages) is ALSO resolved by `flutter pub get` — but a clean `pub add <pkg>` consumer NEVER
  # resolves the package's example. G7 certifies the package's OWN declared hosted constraints,
  # so the dev-only example resolution is removed from the consumer model (a broken bundled
  # example is a real but SEPARATE concern — out of G7's resolution-masking scope).
  rm -rf "$work/example"
  python3 "$G7_STRIP" "$work/pubspec.yaml" 2>/dev/null

  # Flutter vs pure-Dart toolchain (same detection as catalog_census.sh).
  local tool="dart"
  if grep -qE '^[[:space:]]*flutter:[[:space:]]*$' "$pkg/pubspec.yaml" 2>/dev/null \
     && grep -qE 'sdk:[[:space:]]*flutter' "$pkg/pubspec.yaml" 2>/dev/null; then
    tool="flutter"
  fi
  if [[ "$tool" == "flutter" ]] && ! command -v flutter >/dev/null 2>&1; then
    printf '    %-14s SKIP (flutter package but flutter not on PATH — cannot exercise hosted resolve here)\n' "$label"
    return
  fi

  local getlog="$work/_g7_get.log" testlog="$work/_g7_test.log"
  if ! (cd "$work" && "$tool" pub get) >"$getlog" 2>&1; then
    printf '    %-14s FAIL (declared HOSTED sibling constraints will NOT resolve for a clean `pub add %s` — overrides masked this)\n' "$label" "$name"
    sed 's/^/        /' "$getlog" | tail -15
    fail=1
    return
  fi
  if [[ -d "$work/test" ]]; then
    if (cd "$work" && "$tool" test) >"$testlog" 2>&1; then
      printf '    %-14s PASS (hosted resolve OK + tests pass vs published siblings — `pub add %s` works for a clean consumer)\n' "$label" "$name"
    else
      printf '    %-14s FAIL (hosted resolve OK but tests FAIL against PUBLISHED siblings — overrides masked a behavioral skew)\n' "$label"
      sed 's/^/        /' "$testlog" | tail -18
      fail=1
    fi
  else
    printf '    %-14s PASS (hosted resolve OK; package ships no test/ dir to exercise)\n' "$label"
  fi
}

# hosted_resolve_sweep — G7 across every override-bearing package in the catalog.
hosted_resolve_sweep() {
  echo ">> G7 hosted-resolve sweep — every override-bearing package, resolved against PUBLISHED siblings"
  echo "   Reproduces 'pub add <pkg>' for a clean consumer: strip dependency_overrides, then pub get + test vs pub.dev."
  local any=0 pkg name
  for pkg in "$PKG_ROOT"/*/; do
    pkg="${pkg%/}"; name="$(basename "$pkg")"
    [[ -f "$pkg/pubspec.yaml" ]] || continue
    grep -qE '^dependency_overrides:' "$pkg/pubspec.yaml" 2>/dev/null || continue
    any=1
    echo ">> $name  (v$(grep -m1 '^version:' "$pkg/pubspec.yaml" | awk '{print $2}'))"
    hosted_resolve_gate "$pkg" "$name"
  done
  [[ "$any" -eq 1 ]] || echo "   (no override-bearing packages found under $PKG_ROOT)"
  return "$fail"
}

if [[ "${1:-}" == "--hosted-resolve-sweep" ]]; then hosted_resolve_sweep; exit $?; fi
if [[ "${1:-}" == "--g7" ]]; then            # run ONLY the G7 hosted-resolve gate per named package
  shift
  [[ $# -ge 1 ]] || { echo "usage: $0 --g7 <pkg> [<pkg> ...]" >&2; exit 2; }
  for name in "$@"; do
    pkg="$PKG_ROOT/$name"
    if [[ ! -f "$pkg/pubspec.yaml" ]]; then echo ">> $name  — NOT A PACKAGE"; fail=1; continue; fi
    echo ">> $name  (v$(grep -m1 '^version:' "$pkg/pubspec.yaml" | awk '{print $2}'))"
    hosted_resolve_gate "$pkg" "$name"
  done
  exit "$fail"
fi

if [[ "${1:-}" == "--provenance-sweep" ]]; then provenance_sweep; exit $?; fi
if [[ "${1:-}" == "--g6" ]]; then            # run ONLY the G6 provenance gate per named package
  shift
  [[ $# -ge 1 ]] || { echo "usage: $0 --g6 <pkg> [<pkg> ...]" >&2; exit 2; }
  for name in "$@"; do
    pkg="$PKG_ROOT/$name"
    if [[ ! -f "$pkg/pubspec.yaml" ]]; then echo ">> $name  — NOT A PACKAGE"; fail=1; continue; fi
    echo ">> $name  (v$(grep -m1 '^version:' "$pkg/pubspec.yaml" | awk '{print $2}'))"
    provenance_gate "$pkg" "$name"
  done
  exit "$fail"
fi
if [[ "${1:-}" == "--coherence-only" ]]; then coherence; exit "$fail"; fi
if [[ $# -lt 1 ]]; then echo "usage: $0 <pkg> [<pkg> ...]  |  --coherence-only  |  --provenance-sweep  |  --g6 <pkg>" >&2; exit 2; fi

# ---------------------------------------------------------------------------
# G8 reachability — which KNOWN consumers actually receive this release?
#
# WHY (2026-07-04 vision-alignment audit): landing is not reception. The unit
# published 0.4.x while its ONE verified adopter pinned ^0.3.0 and its OWN
# reference app pinned ^0.3.0 — nobody could receive what we built, and no
# loom measured it ("repo green" had quietly become "done"). G8 reads
# scripts/known_consumers.list and, for each staged release, reports per
# consumer:
#   RECEIVES     the consumer's pin admits the staged version
#   LEFT-BEHIND  the pin excludes it -> FAIL unless an EXPLICIT serve-decision
#                is recorded: a `reach-disposition(<consumer>): ...` line in
#                the CHANGELOG's top entry, or G8_ACCEPT="<pkg>:<consumer>,..."
#   NO-DEP       the consumer does not depend on this package (info)
#   SKIP-NET     remote pubspec unreachable (never block offline; mirrors G6)
#   UNPARSED     constraint syntax not understood -> WARN, human judges
# Honest scope: reads DIRECT one-line dependency constraints only (caret,
# ">=A <B", exact, any); transitive reachability is G7's business; a consumer
# using unusual pubspec formatting yields UNPARSED, never a silent pass.

ver_cmp() { # A B -> 0 eq, 1 gt, 2 lt (numeric triplets; prerelease stripped)
  local i; local -a a b
  read -ra a <<< "${1//./ }"; read -ra b <<< "${2//./ }"
  for i in 0 1 2; do
    local x="${a[i]:-0}" y="${b[i]:-0}"
    x="${x%%[-+]*}"; y="${y%%[-+]*}"
    [[ "$x" =~ ^[0-9]+$ && "$y" =~ ^[0-9]+$ ]] || return 3   # non-numeric -> caller treats as unparsed
    if ((10#$x > 10#$y)); then return 1; fi
    if ((10#$x < 10#$y)); then return 2; fi
  done
  return 0
}
ver_ge() { ver_cmp "$1" "$2" && return 0 || { [[ $? -eq 1 ]] && return 0 || return 1; }; }
ver_lt() { ver_cmp "$1" "$2" && return 1 || { [[ $? -eq 2 ]] && return 0 || return 1; }; }

constraint_admits() { # <constraint> <version> -> 0 yes, 1 no, 2 unparsed
  local c="$1" v="$2"
  c="${c//\'/}"; c="${c//\"/}"; c="$(echo "$c" | xargs)"
  if [[ "$c" == ^* ]]; then
    local base="${c#^}" major upper minor patch rest
    # Guard: non-numeric caret bases are UNPARSED, never a crash (cert F1-adj).
    [[ "$base" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+].*)?$ ]] || return 2
    major="${base%%.*}"
    rest="${base#*.}"; minor="${rest%%.*}"
    patch="${rest#*.}"; patch="${patch%%[-+]*}"
    # Dart caret = leftmost-NON-ZERO component may not change (cert F2):
    #   ^1.2.3 -> <2.0.0 ; ^0.3.0 -> <0.4.0 ; ^0.0.5 -> <0.0.6
    if [[ "$major" == 0 && "$minor" == 0 ]]; then
      upper="0.0.$((patch+1))"
    elif [[ "$major" == 0 ]]; then
      upper="0.$((minor+1)).0"
    else
      upper="$((major+1)).0.0"
    fi
    if ver_ge "$v" "$base" && ver_lt "$v" "$upper"; then return 0; else return 1; fi
  fi
  if [[ "$c" =~ ^\>=([0-9][^[:space:]]*)[[:space:]]+\<([0-9][^[:space:]]*)$ ]]; then
    # Copy BASH_REMATCH BEFORE calling helpers — ver_ge's own =~ clobbers it
    # (cert F1: the range form crashed under set -u on the second bound).
    local lo="${BASH_REMATCH[1]}" hi="${BASH_REMATCH[2]}"
    if ver_ge "$v" "$lo" && ver_lt "$v" "$hi"; then return 0; else return 1; fi
  fi
  if [[ "$c" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    [[ "$c" == "$v" ]] && return 0 || return 1
  fi
  if [[ "$c" == "any" ]]; then return 0; fi
  # Empty is NOT 'any': a map-form dep (git:/path: on the next line) extracts
  # as empty — a git-dep consumer never receives pub.dev releases (cert F5).
  return 2
}

# README install-pin honesty — the pub.dev landing page must not instruct an
# install that can never receive the release it ships in. Second occurrence of
# this class (0.4.2 was cut to fix the first) -> deterministic gate per §3
# repeat-pattern. PASS when README has no pin, or its constraint ADMITS the
# staged version; FAIL when the pin excludes the very release carrying it.
readme_pin_gate() { # <pkgdir> <name> <staged-version>
  local pkg="$1" name="$2" ver="$3"
  [[ -f "$pkg/README.md" ]] || { printf '    %-14s SKIP (no README)\n' "G9 readme-pin"; return; }
  local pins bad=0 line c r
  pins="$(grep -E "^[[:space:]]+$name: *[\^'\">=0-9]" "$pkg/README.md" || true)"
  if [[ -z "$pins" ]]; then printf '    %-14s SKIP (no install pin in README)\n' "G9 readme-pin"; return; fi
  while IFS= read -r line; do
    c="${line#*:}"
    constraint_admits "$c" "$ver" && r=0 || r=$?
    if [[ $r -eq 1 ]]; then
      printf '    %-14s FAIL (README pins %s which EXCLUDES this release %s)\n' "G9 readme-pin" "$(echo "$c" | xargs)" "$ver"
      bad=1; fail=1
    elif [[ $r -eq 2 ]]; then
      printf '    %-14s FAIL (README pin %s unparsed — rewrite the README pin to a parseable form)\n' "G9 readme-pin" "$(echo "$c" | xargs)"
      bad=1; fail=1
    fi
  done <<< "$pins"
  [[ $bad -eq 0 ]] && printf '    %-14s PASS (README pin admits %s)\n' "G9 readme-pin" "$ver"
}

reach_gate() { # <pkgdir> <name> <staged-version>
  local pkg="$1" name="$2" ver="$3"
  local sdir; sdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local reg="$sdir/known_consumers.list" root; root="$(dirname "$sdir")"
  if [[ ! -f "$reg" ]]; then printf '    %-14s SKIP (no known_consumers.list)\n' "G8 reach"; return; fi
  # Disposition search scoped to the ACTUAL top CHANGELOG entry (first `## `
  # heading to the next), not a fixed line window (cert F3: `-A30` both
  # silently renewed stale waivers from the previous entry AND cut off long
  # legitimate entries).
  local top_entry=""
  if [[ -f "$pkg/CHANGELOG.md" ]]; then
    top_entry="$(awk '/^## /{n++; if(n==2) exit} n==1{print}' "$pkg/CHANGELOG.md")"
  fi
  local left=0 unparsed=0 out=""
  while IFS=$'\t' read -r consumer source; do
    [[ -z "$consumer" || "$consumer" == \#* ]] && continue
    local pubspec="" line c r
    case "$source" in
      local:*)
        # A registered local consumer whose pubspec is MISSING is a broken
        # thread, never a silent NO-DEP (cert F4: registry rot must be loud).
        if [[ ! -f "$root/${source#local:}" ]]; then
          out+="        $consumer  MISSING (registered local pubspec $root/${source#local:} not found — fix the registry or the path)"$'\n'
          left=1; continue
        fi
        pubspec="$(cat "$root/${source#local:}" 2>/dev/null)" || true ;;
      github:*)
        local rest="${source#github:}" repo path
        repo="${rest%%:*}"; path="${rest#*:}"
        if ! pubspec="$(curl -fsSL --max-time 10 "https://raw.githubusercontent.com/$repo/HEAD/$path" 2>/dev/null)"; then
          out+="        $consumer  SKIP-NET (pubspec unreachable)"$'\n'; continue
        fi ;;
      *)
        # Registry rot on the SCHEME field must not ride a green gate
        # (re-cert condition 1 / Case S — the source-axis sibling of F4/F7).
        out+="        $consumer  UNPARSED source '$source' — fix the registry line"$'\n'
        unparsed=1; continue ;;
    esac
    # Read ONLY the `dependencies:` section — a bare `<name>:` key also appears
    # under `dependency_overrides:` (path overrides) and must not match.
    line="$(printf '%s\n' "$pubspec" | awk -v pkg="$name" '
      /^dependencies:/       {sec=1; next}
      /^[A-Za-z_]+:/         {sec=0}
      sec && $0 ~ "^  "pkg":" {print; exit}')" || true
    if [[ -z "$line" ]]; then out+="        $consumer  NO-DEP"$'\n'; continue; fi
    c="${line#*:}"
    constraint_admits "$c" "$ver" && r=0 || r=$?
    if [[ $r -eq 0 ]]; then
      out+="        $consumer  RECEIVES ($(echo "$c" | xargs) admits $ver)"$'\n'
    elif [[ $r -eq 2 ]]; then
      # UNPARSED must not silently ride a PASS headline (cert F7: "human
      # judges" needs teeth). Acknowledge via the same G8_ACCEPT mechanism.
      if [[ ",${G8_ACCEPT:-}," == *",$name:$consumer,"* ]]; then
        out+="        $consumer  UNPARSED constraint '$(echo "$c" | xargs)' (acknowledged via G8_ACCEPT)"$'\n'
      else
        out+="        $consumer  UNPARSED constraint '$(echo "$c" | xargs)' — judge by hand, then acknowledge (G8_ACCEPT=$name:$consumer)"$'\n'
        unparsed=1
      fi
    else
      if printf '%s' "$top_entry" | grep -qi "reach-disposition($consumer)" \
         || [[ ",${G8_ACCEPT:-}," == *",$name:$consumer,"* ]]; then
        out+="        $consumer  LEFT-BEHIND (accepted: recorded serve-decision) — pin $(echo "$c" | xargs) excludes $ver"$'\n'
      else
        out+="        $consumer  LEFT-BEHIND — pin $(echo "$c" | xargs) excludes $ver; SERVE-DECISION REQUIRED (lift the pin / backport / \`reach-disposition($consumer): <why>\` in the CHANGELOG top entry / G8_ACCEPT=$name:$consumer)"$'\n'
        left=1
      fi
    fi
  done < "$reg"
  if [[ $left -eq 0 && $unparsed -eq 0 ]]; then
    printf '    %-14s PASS\n' "G8 reach"
  elif [[ $left -eq 0 ]]; then
    printf '    %-14s FAIL (an UNPARSED consumer constraint is unacknowledged — judge it, then G8_ACCEPT)\n' "G8 reach"; fail=1
  else
    printf '    %-14s FAIL (a known consumer is LEFT-BEHIND or MISSING with no recorded serve-decision)\n' "G8 reach"; fail=1
  fi
  printf '%s' "$out"
}

for name in "$@"; do
  pkg="$PKG_ROOT/$name"
  if [[ ! -f "$pkg/pubspec.yaml" ]]; then echo ">> $name  — NOT A PACKAGE ($pkg/pubspec.yaml missing)"; fail=1; continue; fi
  ver="$(grep -m1 '^version:' "$pkg/pubspec.yaml" | awk '{print $2}')"
  echo ">> $name  (v$ver)"
  # gates run in the PARENT shell (cd is inside the command) so fail propagates.
  gate "G1 pub-get"   bash -c "cd '$pkg' && dart pub get"
  gate "G2 analyze"   bash -c "cd '$pkg' && dart analyze"
  # Flutter-dependent packages need the flutter runner: `dart test` compiles
  # the Flutter framework sources under the standalone runner and dies inside
  # the SDK (found 2026-07-04 gating routing_bloc — the first Flutter package
  # through G3).
  if [[ -d "$pkg/test" ]]; then
    if grep -q 'sdk: flutter' "$pkg/pubspec.yaml" 2>/dev/null; then
      gate "G3 test" bash -c "cd '$pkg' && flutter test"
    else
      gate "G3 test" bash -c "cd '$pkg' && dart test"
    fi
  else printf '    %-14s NONE (no test/ dir)\n' "G3 test"; fi
  dryrun_gate "$pkg"
  provenance_gate "$pkg" "$name"
  hosted_resolve_gate "$pkg" "$name"
  readme_pin_gate "$pkg" "$name" "$ver"
  reach_gate "$pkg" "$name" "$ver"
done

echo
coherence "$@"
echo
if [[ "$fail" -eq 0 ]]; then
  echo "ALL GATES PASS — candidates are build/test/publish-ready (STAGED items land on commit+republish)."
  echo "Next: adversarial-verify (multi-gate-package-update workflow) + Chair republish gate (§1)."
else
  echo "GATE FAILURE — do not propose a republish until red gates are green."
fi
exit "$fail"
