#!/usr/bin/env bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGES=(
  "navigation_safety"
  "map_viewport_bloc"
  "routing_bloc"
  "offline_tiles"
)

RUN_LOCAL=1
RUN_APP=1
RUN_PUBDEV=1
STRICT_PUBDEV=0

FAILURES=()
WARNINGS=()

usage() {
  cat <<'EOF'
Usage: ./scripts/g3_batch_check.sh [options]

Checks the Sprint 51 G3 publication batch locally and on pub.dev.

Options:
  --pubdev-only     Only check pub.dev package status.
  --local-only      Only run local package and app verification.
  --skip-app        Skip root app verification during local checks.
  --strict-pubdev   Treat pending pub.dev analysis as a failure.
  --help            Show this help text.
EOF
}

add_failure() {
  FAILURES+=("$1")
}

add_warning() {
  WARNINGS+=("$1")
}

run_logged() {
  local dir="$1"
  local label="$2"
  shift 2

  local log_file
  log_file="$(mktemp)"

  printf '==> %s\n' "$label"
  if (cd "$dir" && "$@") >"$log_file" 2>&1; then
    printf 'PASS: %s\n' "$label"
  else
    printf 'FAIL: %s\n' "$label"
    tail -n 20 "$log_file"
    add_failure "$label"
  fi

  rm -f "$log_file"
}

extract_first_match() {
  local text="$1"
  local pattern="$2"
  printf '%s' "$text" | grep -oE "$pattern" | head -n 1
}

extract_health_points() {
  local html="$1"
  local compact
  local tail

  compact="$(printf '%s' "$html" | tr '\n' ' ')"
  tail="${compact#*packages-score packages-score-health}"
  if [[ "$tail" == "$compact" ]]; then
    return
  fi

  printf '%s' "$tail" \
    | grep -oE 'packages-score-value-number">[0-9-]+' \
    | head -n 1 \
    | sed -E 's/.*">([0-9-]+)$/\1/'
}

check_pubdev_package() {
  local package="$1"
  local url="https://pub.dev/packages/$package"
  local html
  local compact_html
  local version
  local points
  local status
  local license

  printf '==> pub.dev: %s\n' "$package"
  if ! html="$(curl -L -s "$url")"; then
    printf 'FAIL: pub.dev fetch failed for %s\n' "$package"
    add_failure "pub.dev fetch: $package"
    return
  fi

  version="$(extract_first_match "$html" "$package [0-9]+\.[0-9]+\.[0-9]+")"
  version="${version#${package} }"
  points="$(extract_health_points "$html")"
  compact_html="$(printf '%s' "$html" | tr '\n' ' ')"

  if printf '%s' "$compact_html" | grep -q '\[pending analysis\]'; then
    status="pending-analysis"
  else
    status="scored"
  fi

  if printf '%s' "$compact_html" | grep -q "BSD-3-Clause (<a href=\"/packages/$package/license\""; then
    license="BSD-3-Clause"
  elif printf '%s' "$compact_html" | grep -q "(pending) (<a href=\"/packages/$package/license\""; then
    license="pending"
  else
    license="unknown"
  fi

  printf 'STATUS: package=%s version=%s pubdev=%s points=%s license=%s\n' \
    "$package" "${version:-unknown}" "$status" "${points:-unknown}" "$license"

  if [[ "$status" == "pending-analysis" ]]; then
    if [[ "$STRICT_PUBDEV" -eq 1 ]]; then
      add_failure "pub.dev pending analysis: $package"
    else
      add_warning "pub.dev pending analysis: $package"
    fi
  fi

  if [[ "$license" == "pending" ]]; then
    if [[ "$STRICT_PUBDEV" -eq 1 ]]; then
      add_failure "pub.dev pending license: $package"
    else
      add_warning "pub.dev pending license: $package"
    fi
  fi
}

run_local_package_checks() {
  local package

  for package in "${PACKAGES[@]}"; do
    run_logged "$ROOT_DIR/packages/$package" "$package flutter test" flutter test
    run_logged "$ROOT_DIR/packages/$package" "$package flutter analyze" flutter analyze
    run_logged "$ROOT_DIR/packages/$package" "$package flutter pub publish --dry-run" flutter pub publish --dry-run
  done
}

run_app_checks() {
  run_logged "$ROOT_DIR" "root flutter pub get" flutter pub get
  run_logged "$ROOT_DIR" "root flutter test --exclude-tags=probe" flutter test --exclude-tags=probe
  run_logged "$ROOT_DIR" "root flutter analyze --no-fatal-infos" flutter analyze --no-fatal-infos
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pubdev-only)
      RUN_LOCAL=0
      RUN_APP=0
      RUN_PUBDEV=1
      ;;
    --local-only)
      RUN_LOCAL=1
      RUN_APP=1
      RUN_PUBDEV=0
      ;;
    --skip-app)
      RUN_APP=0
      ;;
    --strict-pubdev)
      STRICT_PUBDEV=1
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n\n' "$1"
      usage
      exit 2
      ;;
  esac
  shift
done

if [[ "$RUN_LOCAL" -eq 1 ]]; then
  run_local_package_checks
fi

if [[ "$RUN_APP" -eq 1 ]]; then
  run_app_checks
fi

if [[ "$RUN_PUBDEV" -eq 1 ]]; then
  for package in "${PACKAGES[@]}"; do
    check_pubdev_package "$package"
  done
fi

printf '\nSummary\n'
printf 'Failures: %d\n' "${#FAILURES[@]}"
for failure in "${FAILURES[@]}"; do
  printf '  - %s\n' "$failure"
done

printf 'Warnings: %d\n' "${#WARNINGS[@]}"
for warning in "${WARNINGS[@]}"; do
  printf '  - %s\n' "$warning"
done

if [[ ${#FAILURES[@]} -gt 0 ]]; then
  exit 1
fi

exit 0