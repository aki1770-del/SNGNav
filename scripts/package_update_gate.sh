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
trap 'rm -rf "$G6_TMP"' EXIT
G6_VERPARSE="$G6_TMP/verparse.py"
G6_CLASSIFY="$G6_TMP/classify.py"

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

for name in "$@"; do
  pkg="$PKG_ROOT/$name"
  if [[ ! -f "$pkg/pubspec.yaml" ]]; then echo ">> $name  — NOT A PACKAGE ($pkg/pubspec.yaml missing)"; fail=1; continue; fi
  ver="$(grep -m1 '^version:' "$pkg/pubspec.yaml" | awk '{print $2}')"
  echo ">> $name  (v$ver)"
  # gates run in the PARENT shell (cd is inside the command) so fail propagates.
  gate "G1 pub-get"   bash -c "cd '$pkg' && dart pub get"
  gate "G2 analyze"   bash -c "cd '$pkg' && dart analyze"
  if [[ -d "$pkg/test" ]]; then gate "G3 test" bash -c "cd '$pkg' && dart test"; else printf '    %-14s NONE (no test/ dir)\n' "G3 test"; fi
  dryrun_gate "$pkg"
  provenance_gate "$pkg" "$name"
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
