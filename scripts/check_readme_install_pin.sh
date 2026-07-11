#!/usr/bin/env bash
# Assert that every package README's own install pin matches its pubspec version.
#
# Why this exists (BOD-19, 2026-07-12):
#
# Four READMEs in the honest-absence wave — routing_engine, snow_rendering,
# driving_conditions, route_condition_forecast — still pinned the RECALLED
# version in their install snippet:
#
#     dependencies:
#       routing_engine: ^0.5.0      # the Null Island version
#
# For a 0.x package a caret does NOT admit the next minor, so a developer who
# lands on the FIXED package's pub.dev page and copies the documented install
# line gets the DEFECTIVE release. That is the silent recall the Chair forbade,
# reinstated at the point of first contact: the CHANGELOG says "take this
# upgrade deliberately", and the landing page hands them the version that
# fabricates +5.0 °C / Null Island / "Conditions normal".
#
# A doc claiming a property the code lacks is the certificate of a defect
# (AAA's binding finding). This is the cheap mechanical loom for the
# instance of it that is actually deterministic: a version string equality.
#
# Usage:  scripts/check_readme_install_pin.sh [package ...]
#         (no args = every package under packages/)
# Exit:   0 = all pins agree, 1 = at least one README pins a stale version.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

pkgs=("$@")
if [ ${#pkgs[@]} -eq 0 ]; then
  mapfile -t pkgs < <(find packages -maxdepth 1 -mindepth 1 -type d -printf '%f\n' | sort)
fi

fail=0
checked=0

for p in "${pkgs[@]}"; do
  pubspec="packages/$p/pubspec.yaml"
  readme="packages/$p/README.md"
  [ -f "$pubspec" ] || continue
  [ -f "$readme" ] || continue

  version=$(grep -m1 '^version:' "$pubspec" | sed 's/^version:[[:space:]]*//' | tr -d '[:space:]')
  [ -n "$version" ] || continue

  # The install pin the README teaches: a `  <pkg>: ^X.Y.Z` line.
  pin=$(grep -oE "^[[:space:]]+$p:[[:space:]]*\^[0-9]+\.[0-9]+\.[0-9]+" "$readme" | head -1 |
        grep -oE '\^[0-9]+\.[0-9]+\.[0-9]+' | tr -d '^')
  [ -n "$pin" ] || continue

  checked=$((checked + 1))

  # Caret semantics, honestly. `^X.Y.Z` admits everything up to the next
  # BREAKING boundary — and for a 0.x package the breaking boundary is the
  # MINOR, not the major. So:
  #
  #   ^0.4.3  DOES admit 0.4.4   (same 0.4 line — the consumer gets the fix)
  #   ^0.2.7  does NOT admit 0.3.0   <-- this is the harmful case
  #   ^1.2.0  DOES admit 1.3.0
  #
  # Only flag the pin that a consumer's resolver would NOT carry forward to the
  # current version. Flagging a harmless patch drift would make this gate cry
  # wolf, and a loom that cries wolf gets ignored on the day it is right.
  IFS='.' read -r pin_maj pin_min _pin_pat <<<"$pin"
  IFS='.' read -r ver_maj ver_min _ver_pat <<<"$version"

  admits=1
  if [ "$pin_maj" != "$ver_maj" ]; then
    admits=0
  elif [ "$pin_maj" = "0" ] && [ "$pin_min" != "$ver_min" ]; then
    admits=0
  fi

  if [ "$admits" -eq 0 ]; then
    echo "STALE README PIN  $p: README teaches ^$pin, pubspec is $version"
    echo "                  ^$pin does NOT admit $version — a consumer copying the"
    echo "                  README install line gets $pin, i.e. the superseded release."
    fail=1
  fi
done

if [ "$fail" -eq 0 ]; then
  echo "OK: $checked README install pin(s) match their pubspec version."
else
  echo
  echo "A README that pins a superseded version hands the recalled release to"
  echo "the next developer who copies it. Fix the pin before publishing."
fi

exit "$fail"
