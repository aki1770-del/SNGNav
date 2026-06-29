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
# Usage:  ./scripts/catalog_census.sh            # scans the default packages dir
#         PKG_ROOT=/path/to/packages ./scripts/catalog_census.sh

set -u  # error on unset variables; we deliberately do NOT set -e (continue on errors)

PKG_ROOT="${PKG_ROOT:-/home/komada/SNGNav/packages}"

if [[ ! -d "$PKG_ROOT" ]]; then
  echo "ERROR: package root not found: $PKG_ROOT" >&2
  exit 1
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
