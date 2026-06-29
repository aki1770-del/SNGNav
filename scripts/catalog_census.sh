#!/usr/bin/env bash
# catalog_census.sh — reproducible liveness census of the SNGNav package catalog.
#
# For every package directory under packages/ that has a valid pubspec.yaml, this
# runs the four steps an adopting developer's first hour exercises:
#   1. dart pub get   (does it resolve?)
#   2. dart analyze   (does it lint clean?)
#   3. dart test      (do its tests pass?)
#   4. example/main.dart, if present (does first-use run?)
# and prints ONE PASS/FAIL line per package. It does NOT modify, commit, or publish
# anything. Anyone can re-run it to reproduce the 2026-06-26 catalog census.
#
# Notes:
#  - Flutter packages (those depending on the flutter SDK) cannot be exercised by the
#    bare `dart` toolchain; they are reported FLUTTER-SKIP for the dart-only steps.
#  - This is intentionally NOT fail-fast: one bad package never stops the sweep.
#
# Usage:  ./scripts/catalog_census.sh            # buildability census (default)
#         ./scripts/catalog_census.sh coherence  # publish-coherence audit (live==committed)
#         PKG_ROOT=/path/to/packages ./scripts/catalog_census.sh
#         COHERENCE_REF=origin/main ./scripts/catalog_census.sh coherence

set -u  # error on unset variables; we deliberately do NOT set -e (continue on errors)

PKG_ROOT="${PKG_ROOT:-/home/komada/SNGNav/packages}"
REPO_ROOT="$(cd "$PKG_ROOT/.." && pwd)"
COHERENCE_REF="${COHERENCE_REF:-origin/main}"   # ref whose committed version must match pub.dev

if [[ ! -d "$PKG_ROOT" ]]; then
  echo "ERROR: package root not found: $PKG_ROOT" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# coherence mode  (./catalog_census.sh coherence)
#
# Proves the publish-coherence invariant for every publishable package:
#     version live on pub.dev  ==  version whose source is committed on $COHERENCE_REF
#     ( and the local working tree is not silently ahead of that )
#
# Catches the failure class learned 2026-06-29: a package PUBLISHED but whose source
# was never pushed (catalog reachable yet invisible/undurable), AND its mirror — a
# version PUSHED to source but never published (a safety/feature fix that never reaches
# an edge developer; e.g. navigation_safety_core 0.10.4's non-finite SafetyScore guard).
# Either way the version a developer `pub add`s is not the version we shipped. Exits
# non-zero on ANY drift, so it works as a release gate or periodic audit. Reads only —
# never publishes, commits, or pushes.
coherence_audit() {
  local drift=0
  printf '%-42s %-10s %-10s %-10s %-18s\n' "PACKAGE" "LOCAL" "COMMITTED" "LIVE" "VERDICT"
  printf '%.0s-' {1..92}; echo
  for pkg in "$PKG_ROOT"/*/; do
    local pj="${pkg}pubspec.yaml"
    [[ -f "$pj" ]] || continue
    local name local_v publish_to committed_v live verdict
    name="$(grep -m1 '^name:' "$pj" | awk '{print $2}')"
    local_v="$(grep -m1 '^version:' "$pj" | awk '{print $2}')"
    publish_to="$(grep -m1 '^publish_to:' "$pj" | awk '{print $2}')"
    committed_v="$(git -C "$REPO_ROOT" show "$COHERENCE_REF:packages/$name/pubspec.yaml" 2>/dev/null | grep -m1 '^version:' | awk '{print $2}')"
    [[ -z "$committed_v" ]] && committed_v="(absent)"

    if [[ "$publish_to" == "none" ]]; then
      verdict="PRIVATE"; live="(private)"
    else
      live="$(curl -s "https://pub.dev/api/packages/$name" | python3 -c "import sys,json
try: print(json.load(sys.stdin)['latest']['version'])
except Exception: print('(unpub)')" 2>/dev/null)"
      if [[ "$committed_v" == "$live" && "$local_v" == "$committed_v" ]]; then
        verdict="OK"
      else
        verdict=""
        [[ "$committed_v" != "$live" ]] && { verdict="DRIFT(commit!=live)"; drift=1; }
        [[ "$local_v" != "$committed_v" ]] && { verdict="${verdict} LOCAL-AHEAD"; drift=1; }
      fi
    fi
    printf '%-42s %-10s %-10s %-10s %-18s\n' "$name" "$local_v" "$committed_v" "$live" "$verdict"
  done
  echo
  if [[ "$drift" -ne 0 ]]; then
    echo "FAIL: at least one package's live pub.dev version != its committed ($COHERENCE_REF) source." >&2
    echo "      A drifted package serves edge developers a version we did not ship. Publish or push to mend." >&2
    return 1
  fi
  echo "OK: every publishable package is coherent (live == committed == local)."
  return 0
}

if [[ "${1:-census}" == "coherence" ]]; then
  coherence_audit
  exit $?
fi

printf '%-40s %-8s %-9s %-9s %-9s\n' "PACKAGE" "PUBGET" "ANALYZE" "TEST" "EXAMPLE"
printf '%.0s-' {1..80}; echo

# Iterate package dirs in stable sorted order.
for pkg in "$PKG_ROOT"/*/; do
  pkg="${pkg%/}"                       # strip trailing slash
  name="$(basename "$pkg")"
  [[ -f "$pkg/pubspec.yaml" ]] || continue   # skip non-packages

  # Flutter packages need the flutter toolchain, not bare dart — flag and skip dart steps.
  if grep -qE '^\s*flutter:\s*$' "$pkg/pubspec.yaml" 2>/dev/null \
     && grep -qE 'sdk:\s*flutter' "$pkg/pubspec.yaml" 2>/dev/null; then
    printf '%-40s %-8s %-9s %-9s %-9s\n' "$name" "FLUTTER" "-SKIP-" "-SKIP-" "-SKIP-"
    continue
  fi

  # Step 1: resolve dependencies.
  if (cd "$pkg" && dart pub get) >/dev/null 2>&1; then pubget="PASS"; else pubget="FAIL"; fi

  # Step 2: static analysis.
  if (cd "$pkg" && dart analyze) >/dev/null 2>&1; then analyze="PASS"; else analyze="FAIL"; fi

  # Step 3: tests (NONE if no test/ dir).
  if [[ -d "$pkg/test" ]]; then
    if (cd "$pkg" && dart test) >/dev/null 2>&1; then test="PASS"; else test="FAIL"; fi
  else
    test="NONE"
  fi

  # Step 4: first-use example, if shipped.
  if [[ -f "$pkg/example/main.dart" ]]; then
    if (cd "$pkg" && dart run example/main.dart) >/dev/null 2>&1; then example="PASS"; else example="FAIL"; fi
  else
    example="NONE"
  fi

  printf '%-40s %-8s %-9s %-9s %-9s\n' "$name" "$pubget" "$analyze" "$test" "$example"
done

echo
echo "Done. PASS = step succeeded, FAIL = step errored, NONE = step not applicable,"
echo "FLUTTER/-SKIP- = Flutter package (run via 'flutter test' instead of bare dart)."
