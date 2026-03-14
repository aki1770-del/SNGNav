#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

reports=()

if [[ -f coverage/lcov.info ]]; then
  reports+=("coverage/lcov.info")
fi

while IFS= read -r -d '' report; do
  reports+=("$report")
done < <(find packages -path '*/coverage/lcov.info' -print0 | sort -z)

if [[ ${#reports[@]} -eq 0 ]]; then
  echo "No coverage reports found." >&2
  exit 1
fi

mkdir -p coverage
merged_output=$(mktemp)

for report in "${reports[@]}"; do
  cat "$report" >> "$merged_output"
  printf '\n' >> "$merged_output"
done

mv "$merged_output" coverage/lcov.info

read -r covered_lines total_lines < <(
  awk -F, '
    /^DA:/ {
      total += 1
      if ($2 > 0) {
        covered += 1
      }
    }
    END {
      print covered + 0, total + 0
    }
  ' coverage/lcov.info
)

coverage_percent=$(awk -v covered="$covered_lines" -v total="$total_lines" '
  BEGIN {
    if (total == 0) {
      print "0.00"
    } else {
      printf "%.2f", (covered / total) * 100
    }
  }
')

cat > coverage/summary.txt <<EOF
reports=${#reports[@]}
covered_lines=$covered_lines
total_lines=$total_lines
line_coverage=$coverage_percent
EOF

echo "Merged ${#reports[@]} coverage reports into coverage/lcov.info"
echo "Line coverage: $covered_lines/$total_lines ($coverage_percent%)"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "## Coverage Summary"
    echo
    echo "- Reports merged: ${#reports[@]}"
    echo "- Line coverage: $covered_lines/$total_lines ($coverage_percent%)"
    echo "- Artifact: \\`coverage/lcov.info\\`"
  } >> "$GITHUB_STEP_SUMMARY"
fi