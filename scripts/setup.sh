#!/bin/bash
# setup.sh — Install system dependencies and verify build
#
# Tested on: Ubuntu 24.04, Ubuntu 22.04
# Requires: sudo access for apt packages
#
# Usage:
#   ./scripts/setup.sh
#
# What this script does:
#   1. Installs system packages (clang, cmake, ninja, GTK3, SQLite)
#   2. Checks Flutter is installed and on PATH
#   3. Runs flutter pub get
#   4. Runs flutter analyze (zero errors expected)
#   5. Runs flutter test
#   6. Builds the release binary
#   7. Reports results

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

cd "$(dirname "$0")/.."
PROJECT_DIR="$(pwd)"

echo "=== SNGNav Setup ==="
echo "Project: $PROJECT_DIR"
echo ""

# Step 1: System packages
echo -e "${YELLOW}[1/6] Installing system dependencies...${NC}"
sudo apt-get update -qq
sudo apt-get install -y -qq \
  clang \
  cmake \
  ninja-build \
  libgtk-3-dev \
  libsqlite3-dev \
  pkg-config
echo -e "${GREEN}[1/6] System dependencies installed.${NC}"

# Step 2: Flutter check
echo -e "${YELLOW}[2/6] Checking Flutter...${NC}"
if ! command -v flutter &> /dev/null; then
  echo -e "${RED}Flutter not found on PATH.${NC}"
  echo "Install Flutter: https://docs.flutter.dev/get-started/install/linux"
  exit 1
fi
FLUTTER_VERSION=$(flutter --version | head -1)
echo "  $FLUTTER_VERSION"
echo -e "${GREEN}[2/6] Flutter found.${NC}"

# Step 3: Dependencies
echo -e "${YELLOW}[3/6] Getting dependencies...${NC}"
flutter pub get
(cd packages/kalman_dr && dart pub get)
(cd packages/routing_engine && dart pub get)
echo -e "${GREEN}[3/6] Dependencies resolved.${NC}"

# Step 4: Analysis
echo -e "${YELLOW}[4/6] Running static analysis...${NC}"
ANALYZE_OUTPUT=$(flutter analyze --no-fatal-infos 2>&1)
ANALYZE_EXIT=$?
if [ $ANALYZE_EXIT -eq 0 ]; then
  echo -e "${GREEN}[4/6] Analysis clean — zero issues.${NC}"
else
  echo "$ANALYZE_OUTPUT"
  echo -e "${YELLOW}[4/6] Analysis found issues (non-fatal).${NC}"
fi

# Step 5: Tests
echo -e "${YELLOW}[5/6] Running tests...${NC}"
TEST_START=$(date +%s)
flutter test --exclude-tags=probe 2>&1 | tail -3
TEST_END=$(date +%s)
TEST_DURATION=$((TEST_END - TEST_START))
echo -e "${GREEN}[5/6] Tests completed in ${TEST_DURATION}s.${NC}"

# Step 6: Build
echo -e "${YELLOW}[6/6] Building release binary...${NC}"
BUILD_START=$(date +%s)
flutter build linux --release -t lib/snow_scene.dart
BUILD_END=$(date +%s)
BUILD_DURATION=$((BUILD_END - BUILD_START))
echo -e "${GREEN}[6/6] Build completed in ${BUILD_DURATION}s.${NC}"

# Summary
echo ""
echo "=== Setup Complete ==="
echo "  Binary: build/linux/x64/release/bundle/sngnav_getting_started"
echo "  Run:    ./examples/run_demo.sh"
echo "  Tests:  ${TEST_DURATION}s"
echo "  Build:  ${BUILD_DURATION}s"
echo ""
echo "For offline tiles, see data/README.md"
