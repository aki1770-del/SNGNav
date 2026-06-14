#!/usr/bin/env bash
# live_briefing.sh — render the SNGNav "Before you drive" briefing on REAL
# current weather for ANY location, in one command.
#
# Why this exists: the flutter-test sandbox has no outbound network, so the
# real fetch is done here (curl, with the provider's required User-Agent) and
# saved to /tmp/livereal/<name>.json; the harness then parses it with the
# product's own MET-Norway mapper and renders the card to a PNG you can look at.
# An edge developer evaluating SNGNav can SEE the product on real data for their
# own region without editing any Dart.
#
# Usage:
#   tool/live_briefing.sh <name> <lat> <lon> [altitude_m] [caption]
# Examples:
#   tool/live_briefing.sh sapporo 43.06 141.35 17
#   tool/live_briefing.sh tromso  69.65  18.96 10 "Tromsø — Arctic winter"
#
# Output: test/widgets/_capture/pretrip_livereal_<name>.png  (open it and look)
set -euo pipefail

if [ "$#" -lt 3 ]; then
  echo "usage: $0 <name> <lat> <lon> [altitude_m] [caption]" >&2
  exit 2
fi

name="$1"; lat="$2"; lon="$3"; alt="${4:-0}"
caption="${5:-LIVE — MET Norway, real fetch ($name)}"

# MET Norway asks every client to send an identifying User-Agent (their ToS).
UA="sngnav_snow_scene github.com/aki1770-del/SNGNav"
url="https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=${lat}&lon=${lon}&altitude=${alt}"

mkdir -p /tmp/livereal
out="/tmp/livereal/${name}.json"
echo "fetch: $url"
http=$(curl -sS -w '%{http_code}' -A "$UA" "$url" -o "$out")
if [ "$http" != "200" ]; then
  echo "MET Norway returned HTTP $http (not 200) — not rendering on bad data." >&2
  exit 1
fi
echo "saved: $out ($(wc -c <"$out") bytes)"

# Render the briefing from the real fetch (skips honestly if the JSON is absent).
LIVE_NAME="$name" LIVE_CAPTION="$caption" \
  flutter test test/widgets/pretrip_briefing_live_real_capture_test.dart

echo
echo "PNG: test/widgets/_capture/pretrip_livereal_${name}.png  — open it and look."
