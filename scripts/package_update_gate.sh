#!/usr/bin/env bash
# package_update_gate.sh — the DETERMINISTIC gates of the multi-gate package-update method.
#
# A package update is never "tested" by a single pass (project policy). The full method has
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
# rides an executable delta. The honest-declaration suppressor is negation-aware (review
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
# The JUDGMENT gate — adversarial verify, advocate!=verifier (project policy §B) — is conducted by
# the `multi-gate-package-update` workflow, NOT this script (free-text judgment is not
# mechanically gateable; claiming it is would be the narration-over-reading failure, project policy).
# The REPUBLISH gate is the project owner. This script reads only; it never publishes,
# commits, or pushes.
#
# Usage:
#   ./scripts/package_update_gate.sh <pkg> [<pkg> ...]     # gate the named update candidates
#   ./scripts/package_update_gate.sh --coherence-only      # just the catalog-wide G5
#   ./scripts/package_update_gate.sh --provenance-sweep    # G6 across the WHOLE catalog
#   ./scripts/package_update_gate.sh --g7 <pkg> [<pkg>...]  # ONLY the G7 hosted-resolve gate
#   ./scripts/package_update_gate.sh --hosted-resolve-sweep # G7 across all override-bearing pkgs
#   ./scripts/package_update_gate.sh --g11 <pkg> [<pkg>...] # ONLY the G11 snippet-oracle gate
#   ./scripts/package_update_gate.sh --self-test            # guard the gate's own wiring
#   PKG_ROOT=/path ./scripts/package_update_gate.sh <pkg>
#   G6_COMPARE_VERSION=0.2.3 ./scripts/package_update_gate.sh <pkg>   # pin G6's compare version
#
# Exit 0 only if every gate passed for every named package (and coherence is clean).

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# PKG_ROOT defaults to THIS checkout's own packages/ tree — the same substrate G11's
# snippet_oracle_gate already resolves via BASH_SOURCE — never a hardcoded other
# checkout (round-5 MUST: one invocation, two trees; after merge the skew flips
# fail-OPEN — a PASS vouched from an unread tree). Env override retained. Exported so
# G5's catalog_census.sh child (which resolves the same default from its own
# location) reads the SAME tree as this invocation.
PKG_ROOT="${PKG_ROOT:-$(dirname "$HERE")/packages}"
export PKG_ROOT
# Every future PASS/FAIL names its substrate: the banner prints the RESOLVED root.
echo ":: package_update_gate — PKG_ROOT=$PKG_ROOT"

fail=0
gate() { # gate <label> <cmd...> ; prints PASS/FAIL, sets fail on error
  local label="$1"; shift
  if "$@" >"$RUN_TMP/pkg_gate_out" 2>&1; then
    printf '    %-14s PASS\n' "$label"
  else
    printf '    %-14s FAIL\n' "$label"; fail=1
    sed 's/^/        /' "$RUN_TMP/pkg_gate_out" | tail -6
  fi
}

# G4 publish-readiness, staging-aware: a STAGED update has uncommitted package files,
# so pub's "N checked-in files are modified in git" warning is EXPECTED (not a defect).
# PASS = 0 warnings; STAGED = the only warning is the git-modified one; FAIL = any real
# content warning (missing example, bad pubspec, oversized, etc.).
# files?/(is|are): pub says "1 checked-in file is modified" for a single staged file —
# the plural-only grep mislabeled that STAGED state FAIL (measured 2026-07-31,
# condition_aggregator round-4 re-gate, one staged dartdoc edit). Held as variables so
# --self-test exercises the WIRED regex, never a drifting copy.
G4_GITMOD_RE="checked-in files? (is|are) modified in git"
G4_COUNT_RE="[0-9]+ checked-in files? (is|are) modified"
dryrun_gate() { # dryrun_gate <pkgdir>
  local out; out="$(cd "$1" && dart pub publish --dry-run 2>&1)"
  if echo "$out" | grep -qiE "Package has 0 warnings"; then
    printf '    %-14s PASS\n' "G4 dry-run"
  elif echo "$out" | grep -qiE "$G4_GITMOD_RE"; then
    local nw; nw="$(echo "$out" | grep -oiE "Package has [0-9]+ warning" | grep -oE '[0-9]+')"
    if [[ "${nw:-1}" -le 1 ]]; then
      local nf; nf="$(echo "$out" | grep -oE "$G4_COUNT_RE" | grep -oE '^[0-9]+')"
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
  local cstat=0
  bash "$HERE/catalog_census.sh" coherence >"$RUN_TMP/coh" 2>&1 || cstat=$?
  # The child's exit status used to be DISCARDED. A DEAD census (PKG_ROOT not found,
  # census file missing, python3/curl absent, child killed) writes no drift lines, the
  # grep below yields zero matches, and the function printed `coherence PASS` off an
  # empty file — a clean bill vouched by a verifier that never ran. A dead verifier
  # renders UNVERIFIED, never *cleared* (project policy), mirroring G11 above.
  #
  # Liveness is judged by the census's OWN terminal verdict marker, NOT by the exit code
  # alone: catalog_census.sh returns 1 for BOTH "drift found" (a real, parseable answer
  # this function must go on to classify) and "could not run at all" (:29-32 vs :79-83).
  # Treating every non-zero as UNVERIFIED would mislabel every genuine drift. Absence of
  # a verdict marker is the signal that separates them, in either exit direction.
  if ! grep -qE '^(OK: every publishable package is coherent|FAIL: at least one package)' "$RUN_TMP/coh"; then
    printf '    %-14s UNVERIFIED (census child exited %s and produced no verdict — a dead verifier is never a clean bill)\n' "coherence" "$cstat"
    sed 's/^/        /' "$RUN_TMP/coh" | tail -6
    fail=1
    return
  fi
  local bad=0 staged=0
  while IFS= read -r line; do
    local pname; pname="$(echo "$line" | awk '{print $1}')"
    if echo "$line" | grep -q "LOCAL-AHEAD" && ! echo "$line" | grep -q "DRIFT"; then
      if [[ " $* " == *" $pname "* ]]; then echo "    $pname  STAGED (expected-ahead — under test)"; staged=1; else echo "    $pname  FAIL (LOCAL-AHEAD, not under test)"; bad=1; fi
    else
      echo "    $pname  FAIL"; bad=1
    fi
  done < <(grep -E "DRIFT|LOCAL-AHEAD" "$RUN_TMP/coh")
  if [[ "$bad" -eq 1 ]]; then fail=1
  elif [[ "$staged" -eq 1 ]]; then echo "    coherence     STAGED — only expected-ahead drift on packages under test"
  else echo "    coherence     PASS — every publishable package coherent"; fi
}

# ---------------------------------------------------------------------------
# G6 provenance — release-provenance gate (recurrence prevention).
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
RUN_TMP="$(mktemp -d "${TMPDIR:-/tmp}/pkg_gate.XXXXXX")" # gate()/coherence()/G11 output (was fixed /tmp/_* paths — collision-unsafe)
trap 'rm -rf "$G6_TMP" "$G7_TMP" "$RUN_TMP"' EXIT
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
# GAP-1 fix (2026-06-30 review): the honest signal must be STRUCTURAL (a changelog-bullet /
# conventional-commit prefix at line start) or a POSITIVE declaration — never an incidental or
# NEGATED word in prose. So "(does not fix ...)" and "non-breaking" must NOT disarm the no-code
# check, while "a breaking change" / "- fix: ..." still do. This also lets an honest correction
# entry that QUOTES a prior "no api change" mislabel pass, because it positively declares the
# change it is documenting. A negation immediately before the token voids it.
honest = False
# The honest-declaration suppressor is STRUCTURAL ONLY (2026-06-30 re-review, GAP-1 final):
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
# GAP-4 (2026-06-30 review): a CHANGELOG with no `## ` version heading yields no detectable
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
    echo ">> $name  (v$(grep -m1 '^version:' "$pkg/pubspec.yaml" | awk '{print $2}'))  @ $pkg"
    hosted_resolve_gate "$pkg" "$name"
  done
  [[ "$any" -eq 1 ]] || echo "   (no override-bearing packages found under $PKG_ROOT)"
  return "$fail"
}

# ---------------------------------------------------------------------------
# G11 snippet-oracle — Loom L35 wired as a STANDING gate (re-gate round 4, 2026-07-31).
#
# tool/snippet_oracle.py compiles every ```dart block a stranger is invited to
# copy (README.md + dartdoc) against the package's own real API; a snippet that
# names a symbol the package does not have HALTs — a lie told to an edge
# developer. Round 3 (condition_aggregator 0.1.0) proved the oracle's
# uri_does_not_exist exact-URI fix with a hand probe and then DELETED the probe;
# proven-once-then-deleted is not INSERTED (L34: a guard is not INSERTED until
# it has been PROVEN to FAIL — and stays able to prove it). This gate makes the
# oracle run STANDING per package; the tool's own `--self-test` keeps the probe.
# The condition_aggregator README NWS block (dart fence :166, its
# `oracle:placeholders` declaration :167 carrying a reader-supplied IMPORT URI)
# is the standing regression
# fixture for that fix: with the fix reverted, extraction yields the
# apostrophe-mangled symbol "t exist: " which no declaration can match -> HALT.
#
# Numbering: G8 (reach) + G9 (readme-pin) live in this file; G10 (git-provenance)
# is taken on keep/patch/publish-provenance-gate + guideline_verified_delivery
# L63. G11 is the next free number (the round-4 brief said "G8"; measured false).
#
# A dead verifier renders UNVERIFIED, never *cleared* (project policy): a missing
# oracle tool / python3 / dart here is a FAIL, not a SKIP — the founding defect
# of this very gate was the verifier existing only as a deleted one-shot.
# ---------------------------------------------------------------------------
snippet_oracle_gate() { # <pkgdir> <name>
  local pkg="$1" label="G11 snippets"
  local sdir; sdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local oracle; oracle="$(dirname "$sdir")/tool/snippet_oracle.py"
  if [[ ! -f "$oracle" ]] || ! command -v python3 >/dev/null 2>&1 || ! command -v dart >/dev/null 2>&1; then
    printf '    %-14s UNVERIFIED (snippet oracle / python3 / dart unavailable — a dead verifier is never a clean bill)\n' "$label"
    fail=1; return
  fi
  if python3 "$oracle" "$pkg" >"$RUN_TMP/g11_out" 2>&1; then
    printf '    %-14s PASS\n' "$label"
    sed 's/^/        /' "$RUN_TMP/g11_out" | head -3
  else
    printf '    %-14s FAIL (a published snippet names symbols the package does not have)\n' "$label"
    sed 's/^/        /' "$RUN_TMP/g11_out" | tail -12
    fail=1
  fi
}


# --child-env-probe (internal, used by --self-test assertion (iv)).
# Reports what a CHILD PROCESS of this gate actually inherits. G5 spawns
# catalog_census.sh as exactly this kind of child, and that child resolves its OWN
# PKG_ROOT default from its own location — so if `export PKG_ROOT` is
# absent, the census silently audits a DIFFERENT tree than the banner names, and no
# amount of grepping this file's text can see it. Only a child can report this.
if [[ "${1:-}" == "--child-env-probe" ]]; then
  bash -c 'echo "CHILD_PKG_ROOT=${PKG_ROOT:-__NOT_EXPORTED__}"'
  exit 0
fi

if [[ "${1:-}" == "--hosted-resolve-sweep" ]]; then hosted_resolve_sweep; exit $?; fi
if [[ "${1:-}" == "--g7" ]]; then            # run ONLY the G7 hosted-resolve gate per named package
  shift
  [[ $# -ge 1 ]] || { echo "usage: $0 --g7 <pkg> [<pkg> ...]" >&2; exit 2; }
  for name in "$@"; do
    pkg="$PKG_ROOT/$name"
    if [[ ! -f "$pkg/pubspec.yaml" ]]; then echo ">> $name  — NOT A PACKAGE"; fail=1; continue; fi
    echo ">> $name  (v$(grep -m1 '^version:' "$pkg/pubspec.yaml" | awk '{print $2}'))  @ $pkg"
    hosted_resolve_gate "$pkg" "$name"
  done
  exit "$fail"
fi

if [[ "${1:-}" == "--g11" ]]; then           # run ONLY the G11 snippet-oracle gate per named package
  shift
  [[ $# -ge 1 ]] || { echo "usage: $0 --g11 <pkg> [<pkg> ...]" >&2; exit 2; }
  for name in "$@"; do
    pkg="$PKG_ROOT/$name"
    if [[ ! -f "$pkg/pubspec.yaml" ]]; then echo ">> $name  — NOT A PACKAGE"; fail=1; continue; fi
    echo ">> $name  (v$(grep -m1 '^version:' "$pkg/pubspec.yaml" | awk '{print $2}'))  @ $pkg"
    snippet_oracle_gate "$pkg" "$name"
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
    echo ">> $name  (v$(grep -m1 '^version:' "$pkg/pubspec.yaml" | awk '{print $2}'))  @ $pkg"
    provenance_gate "$pkg" "$name"
  done
  exit "$fail"
fi
if [[ "${1:-}" == "--coherence-only" ]]; then coherence; exit "$fail"; fi
if [[ $# -lt 1 ]]; then echo "usage: $0 <pkg> [<pkg> ...]  |  --coherence-only  |  --provenance-sweep  |  --g6 <pkg>  |  --g11 <pkg>  |  --self-test" >&2; exit 2; fi

# ---------------------------------------------------------------------------
# G8 reachability — which KNOWN consumers actually receive this release?
#
# WHY (2026-07-04 vision-alignment audit): landing is not reception. The unit
# published 0.4.x while its ONE verified adopter pinned ^0.3.0 and its OWN
# reference app pinned ^0.3.0 — nobody could receive what we built, and no
# nothing measured it ("repo green" had quietly become "done"). G8 reads
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
    # Dart caret upper bound = pub_semver's `nextBreaking`, which increments the MINOR
    # whenever major is 0 — it is NOT npm's "leftmost non-zero component" rule:
    #   ^1.2.3 -> <2.0.0 ; ^0.3.0 -> <0.4.0 ; ^0.0.5 -> <0.1.0  (NOT <0.0.6)
    # MEASURED against the real solver 2026-07-31 (not recalled): a probe package pinning
    # `condition_aggregator: ^0.0.5` resolved to condition_aggregator **0.0.8** (published
    # line 0.0.1..0.0.8). The prior three-branch arithmetic computed <0.0.6 and reported
    # 0.0.8 EXCLUDED. Fail-closed, so it never waved a release through — but it manufactures
    # phantom LEFT-BEHINDs on the whole 0.0.x catalog and trains the operator to reach for
    # G8_ACCEPT, turning the D4 reach gate into a waiver habit. The `patch` capture above is
    # retained: it still normalises prerelease/build suffixes off the base.
    if [[ "$major" == 0 ]]; then
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

# disposition_substance <top-entry-text> <consumer> <constraint> <min-chars>
#   0 = a substantive serve-decision is recorded
#   1 = no reach-disposition marker for this consumer at all
#   2 = the marker is PRESENT but empty//token-only  <- the failure this closes
#
# Scope is the PARAGRAPH the marker opens (marker line to the next blank line),
# so the reason must sit WITH the marker and cannot be borrowed from unrelated
# prose elsewhere in a long entry.
disposition_substance() {
  local entry="$1" consumer="$2" constraint="$3" minchars="$4"
  local para
  para="$(printf '%s\n' "$entry" | awk -v c="reach-disposition($consumer)" '
    index(tolower($0), tolower(c)) { f=1 }
    f { if ($0 ~ /^[[:space:]]*$/) exit; print }')"
  [[ -n "$para" ]] || return 1
  # Everything after the marker itself — the marker is not its own justification.
  local body; body="$(printf '%s' "$para" | sed "s/.*reach-disposition($consumer)[:)]*//I")"
  local n; n="$(printf '%s' "$body" | tr -d '[:space:]' | wc -c)"
  [[ "$n" -ge "$minchars" ]] || return 2
  # Naming THIS consumer's actual pin is proof the author read it. Failing that,
  # the serve must be named in words. Whitespace/quotes normalised on both sides
  # so `'>=0.0.3 <0.1.0'` matches `>=0.0.3 <0.1.0`.
  local nb nc
  nb="$(printf '%s' "$body" | tr -d "[:space:]\"'")"
  nc="$(printf '%s' "$constraint" | tr -d "[:space:]\"'")"
  if [[ -n "$nc" && "$nb" == *"$nc"* ]]; then return 0; fi
  printf '%s' "$body" | grep -qiE 'backport|lift the pin|lifts the pin|in.range|migrat|republish|receiv|serve|restrain' && return 0
  return 2
}

reach_gate() { # <pkgdir> <name> <staged-version>
  local pkg="$1" name="$2" ver="$3"
  # Registry + consumer root derive from PKG_ROOT — the tree UNDER GATE — never from
  # BASH_SOURCE (the script's own location). With PKG_ROOT pointed at another checkout the
  # BASH_SOURCE derivation read THIS checkout's registry and THIS checkout's `local:`
  # pubspecs while gating THAT checkout's package: one PKG_ROOT and one package could print
  # `G8 reach FAIL — LEFT-BEHIND` from one checkout and `PASS — RECEIVES` from another,
  # under an IDENTICAL banner. In the D4 reach gate that skew fails OPEN — toward "everyone
  # receives" — which is the direction that lets a left-behind developer go unnamed. Every
  # G8 verdict below therefore prints the registry path it actually read.
  local root; root="$(dirname "$PKG_ROOT")"
  local reg="$root/scripts/known_consumers.list"
  if [[ ! -f "$reg" ]]; then printf '    %-14s SKIP (no known_consumers.list at %s)\n' "G8 reach" "$reg"; return; fi
  # Disposition search scoped to the ACTUAL top CHANGELOG entry (first `## `
  # heading to the next), not a fixed line window (cert F3: `-A30` both
  # silently renewed stale waivers from the previous entry AND cut off long
  # legitimate entries).
  local top_entry=""
  if [[ -f "$pkg/CHANGELOG.md" ]]; then
    top_entry="$(awk '/^## /{n++; if(n==2) exit} n==1{print}' "$pkg/CHANGELOG.md")"
  fi
  local left=0 unparsed=0 out=""
  # A recorded serve-decision must SAY something. Until now the acceptance test
  # was `grep -qi "reach-disposition($consumer)"` and nothing more, so the bare
  # string `reach-disposition(sngnav-app):` — twenty-nine characters, no reason,
  # no reader served — cleared a D4 reach row. That is a waiver wearing the word
  # "decision", and it fails OPEN in the one gate whose whole purpose is to make
  # a left-behind developer impossible to leave unnamed.
  #
  # Substance floor (both required), scoped to the PARAGRAPH the marker opens —
  # marker line to the next blank line — so the reason must sit WITH the marker
  # and cannot be borrowed from unrelated prose elsewhere in the entry:
  #   (1) >= REACH_DISPOSITION_MIN_CHARS non-space characters after the marker;
  #   (2) it names THIS consumer's actual constraint (proof the author read the
  #       pin) OR names the serve in words (backport / lift / in-range / …).
  # Honest scope, stated rather than sold: this is a FLOOR on effort, not a
  # judge of reasoning. It cannot tell a true serve-decision from a fluent one —
  # that judgment is the project owner's and the adversarial review's (project policy).
  # What it ends is the empty token clearing a dignity row in silence.
  local REACH_DISPOSITION_MIN_CHARS="${REACH_DISPOSITION_MIN_CHARS:-120}"
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
        local rest="${source#github:}" repo path http
        repo="${rest%%:*}"; path="${rest#*:}"
        # A 404 is registry ROT (repo deleted, renamed or gone private) — NOT an outage.
        # `curl -fsSL` collapsed both into SKIP-NET, so a permanently dead consumer row
        # rode a green gate forever under a verdict that reads "try again when online".
        # This is the github: sibling of cert F4 (missing local pubspec = loud MISSING)
        # and Case S (bad scheme = loud UNPARSED); the remaining axis was the only one
        # still failing silent. GONE is loud, and is fixed in the registry, not waived.
        http="$(curl -sSL -o "$RUN_TMP/g8_pubspec" -w '%{http_code}' --max-time 10 \
                "https://raw.githubusercontent.com/$repo/HEAD/$path" 2>/dev/null || echo 000)"
        if [[ "$http" == "404" ]]; then
          out+="        $consumer  GONE (HTTP 404 — $repo/$path no longer exists; fix or retire the registry row, never leave it reading as a transient outage)"$'\n'
          left=1; continue
        elif [[ "$http" != "200" ]]; then
          out+="        $consumer  SKIP-NET (pubspec unreachable, HTTP $http)"$'\n'; continue
        fi
        pubspec="$(cat "$RUN_TMP/g8_pubspec")" ;;
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
      local disp_verdict=""
      disposition_substance "$top_entry" "$consumer" "$(echo "$c" | xargs)" \
        "$REACH_DISPOSITION_MIN_CHARS" && disp_verdict=ok || disp_verdict=$?
      if [[ "$disp_verdict" == "ok" ]] \
         || [[ ",${G8_ACCEPT:-}," == *",$name:$consumer,"* ]]; then
        out+="        $consumer  LEFT-BEHIND (accepted: recorded serve-decision) — pin $(echo "$c" | xargs) excludes $ver"$'\n'
      elif [[ "$disp_verdict" == "2" ]]; then
        # The marker is PRESENT but says nothing. This is louder than a missing
        # disposition, not quieter: someone wrote the token that clears a
        # dignity row and left the reason out.
        out+="        $consumer  LEFT-BEHIND — pin $(echo "$c" | xargs) excludes $ver; reach-disposition($consumer) is PRESENT BUT EMPTY (needs >=$REACH_DISPOSITION_MIN_CHARS chars in its own paragraph, naming the pin $(echo "$c" | xargs) or the serve) — a token is not a serve-decision"$'\n'
        left=1
      else
        out+="        $consumer  LEFT-BEHIND — pin $(echo "$c" | xargs) excludes $ver; SERVE-DECISION REQUIRED (lift the pin / backport / \`reach-disposition($consumer): <why>\` in the CHANGELOG top entry / G8_ACCEPT=$name:$consumer)"$'\n'
        left=1
      fi
    fi
  done < "$reg"
  # Every verdict names the REGISTRY it read: a G8 line without its substrate is exactly
  # the artifact that let two checkouts disagree under one banner.
  if [[ $left -eq 0 && $unparsed -eq 0 ]]; then
    printf '    %-14s PASS  [registry %s]\n' "G8 reach" "$reg"
  elif [[ $left -eq 0 ]]; then
    printf '    %-14s FAIL (an UNPARSED consumer constraint is unacknowledged — judge it, then G8_ACCEPT)  [registry %s]\n' "G8 reach" "$reg"; fail=1
  else
    printf '    %-14s FAIL (a known consumer is LEFT-BEHIND, GONE or MISSING with no recorded serve-decision)  [registry %s]\n' "G8 reach" "$reg"; fail=1
  fi
  printf '%s' "$out"
}

# --g8 — run ONLY the G8 reachability gate per named package. Positioned HERE,
# after reach_gate's definition, because bash resolves a function at CALL time:
# placed with the other single-gate flags (which sit above their helpers) it
# would abort on an undefined function. Mirrors --g6 / --g7 / --g11, and is what
# --self-test's G8 assertions execute instead of describing.
if [[ "${1:-}" == "--g8" ]]; then
  shift
  [[ $# -ge 1 ]] || { echo "usage: $0 --g8 <pkg> [<pkg> ...]" >&2; exit 2; }
  for name in "$@"; do
    pkg="$PKG_ROOT/$name"
    if [[ ! -f "$pkg/pubspec.yaml" ]]; then echo ">> $name  — NOT A PACKAGE"; fail=1; continue; fi
    ver="$(grep -m1 '^version:' "$pkg/pubspec.yaml" | awk '{print $2}')"
    echo ">> $name  (v$ver)  @ $pkg"
    reach_gate "$pkg" "$name" "$ver"
  done
  exit "$fail"
fi

# --self-test — guard THIS GATE'S OWN WIRING (repo convention: fabrication_sweep.sh /
# pds_reach.py --self-test). PROVE THE CHECK: each assertion targets a wiring defect this
# script has ACTUALLY SHIPPED — G11 run once by hand instead of standing in the battery
# (round 4); the plural-only G4 grep mislabeling a 1-file STAGED state FAIL (round 4);
# PKG_ROOT hardcoded to another checkout while the G11 tool resolved via BASH_SOURCE —
# one invocation, two trees (round 5). A gate never shown to FAIL is a green light with
# no thread behind it.
#
# RECORD CORRECTION (round 7, 2026-07-31). Commit 2346396's message states
# "11 self-test cases, 4 coherence cases, 2-checkout G8 agreement" while this
# block at that commit read `total=7` and printed `>> SELF-TEST: 7/7`. Both
# numbers describe real work but they count DIFFERENT things — assertions
# standing in the file (7) versus mutation runs performed while building them
# (11) — and the message says neither, so a reader reconciling the two finds a
# contradiction and no way to resolve it. The assertion count is the one this
# script can prove: it is printed on every run. The mutation count is not
# recoverable from the artifact — round 6's mutations were applied and reverted
# in a working tree and left no trace — so it is recorded here as UNVERIFIABLE
# rather than restated as fact. 2346396 is not amended: the round-7 review cites
# that SHA, and rewriting it to tidy a number would destroy the trail the review
# is working from. The correction runs forward, which is where a reader is.
#
# ROUND 6 (2026-07-31) — countermeasure under a stop-the-line finding on observation-grade(B),
# verification-overstatement. The round-5 (iii) assertion was a TAUTOLOGY: its positive
# grep pattern matched its OWN source line (`grep -nF` returned :91 AND :801), so the
# assertion vouched for itself and passed against three separate mutations of the line it
# claimed to guard. The mutations that exposed it were SUPPLIED BY THE GATE, not chosen by
# the author of the fix — an author-chosen break-proof tests the defect the author already
# imagined. Accordingly: where a property is BEHAVIOURAL, the assertion now EXECUTES the
# behaviour and reads what actually happened, instead of grepping for the shape of source
# it hopes is there. This block is positioned after the helper definitions so it can CALL
# them (constraint_admits) rather than describe them.
if [[ "${1:-}" == "--self-test" ]]; then
  src="${BASH_SOURCE[0]}"
  pass=0; total=12
  echo ">> SELF-TEST: does the gate's own wiring hold?"

  # Wiring assertions read a COMMENT-STRIPPED view of the source. A raw-source grep
  # passes on a commented-out call, so `# snippet_oracle_gate "$pkg" "$name"` would have
  # vouched for a standing gate that no longer runs. (The strip is line-oriented and
  # deliberately simple — it is used ONLY for the wiring greps below, never for parsing.)
  nocomment="$RUN_TMP/src_nocomment"
  sed 's/[[:space:]]*#.*$//' "$src" > "$nocomment"

  # (i) G11 snippet-oracle is LIVE CODE in the per-package BATTERY loop — not only behind
  # --g11, and not commented out. The battery is the column-0 `for name ...` / `done` block.
  battery="$(awk '/^for name in "\$@"; do/{f=1} f{print; if ($0 ~ /^done/) exit}' "$nocomment")"
  if grep -qF 'snippet_oracle_gate "$pkg" "$name"' <<<"$battery"; then
    echo "   PASS  (i)   G11 snippet_oracle_gate wired LIVE (uncommented) in the battery loop"
    pass=$((pass+1))
  else
    echo "   FAIL  (i)   G11 not live in the battery loop — a standing gate that only runs by hand is not standing"
  fi

  # (ii) The G4 git-modified regex matches the SINGULAR pub warning form (round-4 defect),
  # still matches the plural, and the count-extract regex reads the singular count.
  if echo "1 checked-in file is modified in git." | grep -qiE "$G4_GITMOD_RE" \
     && echo "3 checked-in files are modified in git." | grep -qiE "$G4_GITMOD_RE" \
     && [[ "$(echo "1 checked-in file is modified" | grep -oE "$G4_COUNT_RE" | grep -oE '^[0-9]+')" == "1" ]]; then
    echo "   PASS  (ii)  G4 regex matches singular '1 checked-in file is modified' (and plural)"
    pass=$((pass+1))
  else
    echo "   FAIL  (ii)  G4 regex misses a checked-in-modified form — a STAGED state would mislabel FAIL"
  fi

  # (iii) BEHAVIOURAL — PKG_ROOT's default RESOLVES to THIS checkout's packages/. Asserted
  # by EXECUTING the gate in a child with PKG_ROOT unset and reading the root it actually
  # banners. Catches a wrong default HOWEVER SPELLED: $HOME/..., an absolute literal
  # indented to slip a `^` anchor, or an indirected $SOMEVAR/... — none of which a
  # source-shape grep can enumerate in advance.
  expect_root="$(dirname "$(cd "$(dirname "$src")" && pwd)")/packages"
  actual_root="$(env -u PKG_ROOT bash "$src" 2>/dev/null \
                 | grep -m1 '^:: package_update_gate' | sed 's/.*PKG_ROOT=//')"
  if [[ -n "$actual_root" && "$actual_root" == "$expect_root" ]]; then
    echo "   PASS  (iii) PKG_ROOT resolves to this checkout: $actual_root"
    pass=$((pass+1))
  else
    echo "   FAIL  (iii) PKG_ROOT resolved to '${actual_root:-<none>}', expected '$expect_root' — one invocation, two trees"
  fi

  # (iv) BEHAVIOURAL — PKG_ROOT is EXPORTED, observed FROM A CHILD PROCESS. `export
  # PKG_ROOT` carried no guard at all: deleting it left this self-test fully green AND the
  # banner confidently naming the right tree, while G5's catalog_census.sh child fell back
  # to its own hardcoded default (catalog_census.sh:25) and audited the unread main tree.
  # A text grep cannot observe process inheritance; only a child can report it.
  probe_root="$(env -u PKG_ROOT bash "$src" --child-env-probe 2>/dev/null \
                | grep -m1 '^CHILD_PKG_ROOT=' | sed 's/^CHILD_PKG_ROOT=//')"
  if [[ "$probe_root" == "$expect_root" ]]; then
    echo "   PASS  (iv)  a child process inherits PKG_ROOT=$probe_root (the export is live)"
    pass=$((pass+1))
  else
    echo "   FAIL  (iv)  child inherited '${probe_root:-<none>}', expected '$expect_root' — the census child would audit a different source tree than the banner names"
  fi

  # (v) The G4 gate CALL SITES still reference the named regex variables. Round 4 hoisted
  # the regexes into variables so (ii) exercises the WIRED regex — but nothing asserted the
  # call sites still USE them. Re-inlining a literal inside dryrun_gate passed (ii) forever
  # while the wired behaviour drifted away from the thing (ii) proves. Scoped to the
  # FUNCTION BODY: asserting against the whole file would match (ii)'s own lines — the
  # round-5 tautology, one function over.
  dryrun_fn="$(awk '/^dryrun_gate\(\) \{/{f=1} f{print; if ($0 ~ /^\}/) exit}' "$nocomment")"
  if grep -qF 'grep -qiE "$G4_GITMOD_RE"' <<<"$dryrun_fn" \
     && grep -qF 'grep -oE "$G4_COUNT_RE"' <<<"$dryrun_fn"; then
    echo "   PASS  (v)   dryrun_gate references \$G4_GITMOD_RE / \$G4_COUNT_RE (no re-inlined literal)"
    pass=$((pass+1))
  else
    echo "   FAIL  (v)   a G4 call site re-inlined its regex — (ii) would prove a variable the gate no longer uses"
  fi

  # (vi) The six per-package SUBSTRATE STAMPS are present — one per invocation
  # mode (sweep / --g7 / --g11 / --g6 / --g8 / the battery). Deleting them all still passed
  # every prior assertion — a gate that stops naming WHICH tree it read can print a green
  # PASS vouched from anywhere.
  #
  # The PKG_ROOT banner is deliberately NOT grepped here. A source-grep for it is a
  # TAUTOLOGY: the search string appears in the searching line itself, so it reports
  # "present" with the banner deleted — the exact round-5 defect, reproduced while fixing
  # it, and caught only because the mutation harness ran the mutation instead of trusting
  # the fix. The banner is guarded BEHAVIOURALLY by (iii)/(iv), which read the value the
  # banner actually prints from a child process: delete the banner and both go '<none>'.
  # This grep is safe only because the pattern's own source line spells it '@ \$pkg"'
  # (backslash-escaped), which does not match the literal it searches for — verified by
  # the baseline counting the stamps and NOT this line. The count moved 5 -> 6 in round 7
  # when --g8 was added; it is a census of real stamps, so adding an invocation mode
  # without its stamp FAILS here, which is the intent.
  stamps="$(grep -c '@ \$pkg"' "$nocomment")"
  if [[ "$stamps" -eq 6 ]]; then
    echo "   PASS  (vi)  all 6 per-package substrate stamps present (banner covered behaviourally by (iii)/(iv))"
    pass=$((pass+1))
  else
    echo "   FAIL  (vi)  substrate stamps: $stamps of 6 present — a PASS must always name its source tree"
  fi

  # (vii) BEHAVIOURAL — the caret arithmetic agrees with the REAL pub solver, by CALLING
  # constraint_admits rather than reading it. Measured against the live solver 2026-07-31:
  # a probe pinning `condition_aggregator: ^0.0.5` resolved to 0.0.8, so ^0.0.5 is
  # >=0.0.5 <0.1.0 (pub_semver nextBreaking increments the MINOR whenever major is 0) —
  # not npm's <0.0.6. The old arithmetic called 0.0.8 EXCLUDED: fail-closed, but it
  # manufactures phantom LEFT-BEHINDs across the 0.0.x catalog and trains the operator to
  # reach for G8_ACCEPT, turning the D4 reach gate into a waiver habit.
  if constraint_admits "^0.0.5" "0.0.8" && constraint_admits "^0.0.5" "0.0.5" \
     && ! constraint_admits "^0.0.5" "0.1.0" && ! constraint_admits "^0.0.5" "0.0.4" \
     && constraint_admits "^0.3.0" "0.3.9" && ! constraint_admits "^0.3.0" "0.4.0" \
     && constraint_admits "^1.2.3" "1.9.0" && ! constraint_admits "^1.2.3" "2.0.0"; then
    echo "   PASS  (vii) caret arithmetic matches the real solver (^0.0.5 admits 0.0.8, excludes 0.1.0)"
    pass=$((pass+1))
  else
    echo "   FAIL  (vii) caret arithmetic disagrees with the real pub solver on the 0.0.x line"
  fi

  # ROUND 7 (2026-07-31) — the round-6 fixes were BEHAVIOURAL and three of them
  # shipped with NO guard at all: reverting each left this self-test fully green.
  # Verified before building (mutations supplied by the round-7 verifier, not
  # chosen here): stubbing catalog_census.sh to `exit 127` made a REVERTED
  # coherence() print `coherence PASS` off a verifier that never ran, at 7/7;
  # restoring reach_gate's BASH_SOURCE registry derivation, and collapsing the
  # 404 GONE branch back into SKIP-NET, each also stayed 7/7. A fix whose
  # reversal is invisible to the self-test is not guarded — it is remembered.
  #
  # (viii)-(xii) below therefore RUN the gate and read what it actually printed.

  # (viii) BEHAVIOURAL — coherence renders UNVERIFIED on a DEAD census, and does
  # NOT mislabel a live one. Executed against a throwaway copy of this script
  # beside a stub census, so all three directions are deterministic and offline.
  ct_dir="$RUN_TMP/coh_selftest"; mkdir -p "$ct_dir"
  cp "$src" "$ct_dir/gate.sh"
  coh_case() { # coh_case <census-body> ; echoes the coherence verdict line
    printf '%s\n' '#!/usr/bin/env bash' "$1" > "$ct_dir/catalog_census.sh"
    chmod +x "$ct_dir/catalog_census.sh"
    PKG_ROOT="$expect_root" bash "$ct_dir/gate.sh" --coherence-only 2>&1 \
      | grep -E '^ {4}(coherence|[a-z_]+ +(FAIL|STAGED))' | head -1
  }
  coh_dead="$(coh_case 'exit 127')"
  coh_clean="$(coh_case 'echo "OK: every publishable package is coherent"; exit 0')"
  coh_drift="$(coh_case 'echo "snow_rendering  DRIFT live=0.2.9 local=0.3.0"; echo "FAIL: at least one package is incoherent"; exit 1')"
  if [[ "$coh_dead" == *UNVERIFIED* ]] \
     && [[ "$coh_clean" == *PASS* ]] \
     && [[ "$coh_drift" == *FAIL* && "$coh_drift" != *UNVERIFIED* ]]; then
    echo "   PASS  (viii) coherence: dead census => UNVERIFIED, clean => PASS, drift => FAIL (not mislabeled)"
    pass=$((pass+1))
  else
    echo "   FAIL  (viii) coherence liveness: dead='$coh_dead' clean='$coh_clean' drift='$coh_drift'"
  fi

  # (ix) BEHAVIOURAL — reach_gate reads the registry under PKG_ROOT (the tree
  # UNDER GATE), never under the script's own location. Asserted by running --g8
  # against a throwaway tree and reading the registry path the verdict NAMES: with
  # the BASH_SOURCE derivation restored this prints THIS checkout's registry while
  # gating the temp tree's package — two trees, one banner, failing OPEN in the
  # D4 gate. Offline: the registry holds only a `local:` row.
  g8_root="$RUN_TMP/g8tree"
  mkdir -p "$g8_root/packages/probe_pkg" "$g8_root/scripts" "$g8_root/consumer"
  printf 'name: probe_pkg\nversion: 9.9.9\n' > "$g8_root/packages/probe_pkg/pubspec.yaml"
  printf 'name: c\ndependencies:\n  probe_pkg: ^1.0.0\n' > "$g8_root/consumer/pubspec.yaml"
  printf 'probe-consumer\tlocal:consumer/pubspec.yaml\n' > "$g8_root/scripts/known_consumers.list"
  g8_out="$(PKG_ROOT="$g8_root/packages" bash "$src" --g8 probe_pkg 2>&1)"
  if grep -q "registry $g8_root/scripts/known_consumers.list" <<<"$g8_out"; then
    echo "   PASS  (ix)  G8 reads the registry under PKG_ROOT, and names it in the verdict"
    pass=$((pass+1))
  else
    echo "   FAIL  (ix)  G8 named a registry outside the tree under gate — one PKG_ROOT, two trees:"
    sed 's/^/          /' <<<"$g8_out" | head -3
  fi

  # (x) BEHAVIOURAL — registry ROT is loud and transport failure is not. A 404
  # (repo deleted / renamed / private) must render GONE; anything else must stay
  # SKIP-NET so the gate never blocks offline. `curl -fsSL` collapsed the two, so a
  # permanently dead consumer row rode a green gate under a verdict that reads as a
  # transient outage. Both directions forced with a stub curl on PATH — deterministic
  # and network-free, so the assertion cannot itself go dark when the network does.
  fake_bin="$RUN_TMP/fakebin"; mkdir -p "$fake_bin"
  cat > "$fake_bin/curl" <<'FAKECURL'
#!/usr/bin/env bash
out=""; prev=""
for a in "$@"; do [[ "$prev" == "-o" ]] && out="$a"; prev="$a"; done
[[ -n "$out" ]] && : > "$out"
echo "${FAKE_HTTP_CODE:-000}"
FAKECURL
  chmod +x "$fake_bin/curl"
  printf 'probe-consumer\tgithub:someone/deleted-repo:pubspec.yaml\n' > "$g8_root/scripts/known_consumers.list"
  g8_404="$(PATH="$fake_bin:$PATH" FAKE_HTTP_CODE=404 PKG_ROOT="$g8_root/packages" bash "$src" --g8 probe_pkg 2>&1)"
  g8_503="$(PATH="$fake_bin:$PATH" FAKE_HTTP_CODE=503 PKG_ROOT="$g8_root/packages" bash "$src" --g8 probe_pkg 2>&1)"
  if grep -q 'GONE' <<<"$g8_404" && grep -q 'SKIP-NET' <<<"$g8_503" \
     && ! grep -q 'GONE' <<<"$g8_503"; then
    echo "   PASS  (x)   G8: HTTP 404 => GONE (registry rot), other failures => SKIP-NET (never blocks offline)"
    pass=$((pass+1))
  else
    echo "   FAIL  (x)   G8 collapsed registry rot into a transient outage — a dead consumer row would ride a green gate"
  fi

  # (xi) EVERY per-package gate is live in the battery, not only G11. The round-6
  # assertion (i) guarded exactly one call site, so commenting out the battery's
  # `reach_gate` call — deleting the D4 reach gate outright — still scored 7/7.
  # A wiring guard that covers one of nine gates is a guard for that one gate.
  missing_wiring=""
  for callsite in 'gate "G1 pub-get"' 'gate "G2 analyze"' 'gate "G3 test"' \
                  'dryrun_gate "$pkg"' 'provenance_gate "$pkg" "$name"' \
                  'hosted_resolve_gate "$pkg" "$name"' \
                  'readme_pin_gate "$pkg" "$name" "$ver"' \
                  'reach_gate "$pkg" "$name" "$ver"' \
                  'snippet_oracle_gate "$pkg" "$name"'; do
    grep -qF "$callsite" <<<"$battery" || missing_wiring+=" ${callsite%% *}:${callsite}"
  done
  if [[ -z "$missing_wiring" ]]; then
    echo "   PASS  (xi)  all 9 per-package gates wired LIVE in the battery (D4 reach gate included)"
    pass=$((pass+1))
  else
    echo "   FAIL  (xi)  gate(s) missing from the battery loop:$missing_wiring"
  fi

  # (xii) BEHAVIOURAL — a recorded serve-decision must SAY something. The
  # acceptance test was a bare `grep -qi "reach-disposition($consumer)"`, so the
  # token alone cleared a D4 row. Asserted by CALLING disposition_substance:
  # bare token => 2 (present but empty), substantive => 0, absent => 1.
  bare_entry='## 1.0.0
reach-disposition(probe-consumer):

Some other paragraph entirely, long enough to pass a length test on its own if
the scope were the whole entry rather than the paragraph the marker opens.'
  good_entry="## 1.0.0
reach-disposition(probe-consumer): not migrating this cycle — the pin ^1.0.0
excludes 9.9.9, and the substance already reached this consumer in range at
1.0.4, so no republish is owed and nobody is left unnamed."
  disposition_substance "$bare_entry" "probe-consumer" "^1.0.0" 120; d_bare=$?
  disposition_substance "$good_entry" "probe-consumer" "^1.0.0" 120; d_good=$?
  disposition_substance "## 1.0.0
nothing here" "probe-consumer" "^1.0.0" 120; d_none=$?
  if [[ "$d_bare" -eq 2 && "$d_good" -eq 0 && "$d_none" -eq 1 ]]; then
    echo "   PASS  (xii) a bare reach-disposition token does NOT clear a D4 row (bare=2 substantive=0 absent=1)"
    pass=$((pass+1))
  else
    echo "   FAIL  (xii) disposition substance: bare=$d_bare (want 2) substantive=$d_good (want 0) absent=$d_none (want 1)"
  fi

  echo
  echo ">> SELF-TEST: $pass/$total"
  [[ "$pass" == "$total" ]] || exit 1
  exit 0
fi

for name in "$@"; do
  pkg="$PKG_ROOT/$name"
  if [[ ! -f "$pkg/pubspec.yaml" ]]; then echo ">> $name  — NOT A PACKAGE ($pkg/pubspec.yaml missing)"; fail=1; continue; fi
  ver="$(grep -m1 '^version:' "$pkg/pubspec.yaml" | awk '{print $2}')"
  echo ">> $name  (v$ver)  @ $pkg"
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
  snippet_oracle_gate "$pkg" "$name"
done

echo
coherence "$@"
echo
if [[ "$fail" -eq 0 ]]; then
  echo "ALL GATES PASS — candidates are build/test/publish-ready (STAGED items land on commit+republish)."
  echo "Next: adversarial-verify (multi-gate-package-update workflow) + owner republish gate."
else
  echo "GATE FAILURE — do not propose a republish until red gates are green."
fi
exit "$fail"
