#!/usr/bin/env bash
# Process-fix C (D-VGC218-1): publish pub.dev packages ONLY from the embedded-target Dart SDK
# (Flutter 3.38.3 / Dart 3.10.1), and REFUSE to publish any package whose environment.sdk lower
# bound is above the target. Root cause of the ^3.11.0-floor catalog skew was publishing from a
# host SDK (Dart 3.12) that stamped a 3.11 floor, locking out the embedded IVI target. This guard
# makes that recurrence impossible. NOTE: this is the MECHANISM only — per D-VGC218-1 tooth 6 the
# AUTHORITY to publish is Komada-voice per-act + Vice SEO + L28-γ/register + OPS-RULE-062(C) assert.
set -euo pipefail
PKG_DIR="${1:?usage: publish-from-target-dart.sh <package-dir> (set PUBLISH=1 to actually publish)}"
SDK="${TARGET_FLUTTER_SDK:-/home/komada/flutter-sdks/flutter-3.38.3}"
DART="$SDK/bin/dart"
cd "$PKG_DIR"

# 1. Assert the publishing SDK is the embedded target (Dart 3.10.x)
"$DART" --version 2>&1 | grep -q '3\.10\.' || { echo "REFUSE: publish SDK is not Dart 3.10.x"; exit 1; }

# 2. Assert the package floor does not exceed the target (no ^3.11+ floor)
floor=$(grep -A2 '^environment:' pubspec.yaml | grep -oE 'sdk:[^#]*' | grep -oE '3\.[0-9]+' | head -1)
major=${floor%.*}; minor=${floor#*.}
if [ "$major" -ne 3 ] || [ "$minor" -gt 10 ]; then
  echo "REFUSE: pubspec environment.sdk floor '$floor' > 3.10 — would lock out the embedded target"; exit 1
fi
echo "OK: SDK Dart 3.10.x, package floor $floor <= target."

# 3. Dry-run; publish only on explicit PUBLISH=1 (caller must have the per-act gate cleared)
"$DART" pub publish --dry-run
if [ "${PUBLISH:-0}" = "1" ]; then
  echo ">>> PUBLISH=1 set — publishing $(basename "$PKG_DIR") from Dart 3.10.x"
  "$DART" pub publish --force
else
  echo "Dry-run clean. Re-run with PUBLISH=1 (after the per-act gate) to publish."
fi
