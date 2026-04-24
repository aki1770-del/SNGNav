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
#   3. Runs flutter pub get for the root app and every monorepo sibling package
#   4. Runs flutter analyze (zero errors/warnings expected; infos non-fatal)
#   5. Runs the disk-bounded monorepo test runner (scripts/test_runner.sh)
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
if ! sudo -n true 2>/dev/null; then
  echo "  Step 1 needs interactive sudo access on Debian/Ubuntu."
  echo "  You may be prompted for your password, or you can install these manually first:"
  echo "    sudo apt-get install clang cmake ninja-build libgtk-3-dev libsqlite3-dev pkg-config"
fi
if ! sudo -v; then
  echo -e "${RED}Unable to acquire sudo credentials for Step 1.${NC}"
  exit 1
fi
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

# Step 3: Dependencies (root app + all monorepo sibling packages)
echo -e "${YELLOW}[3/6] Getting dependencies...${NC}"
echo "  root app..."
flutter pub get
for pkg in packages/*/; do
  pkg_name=$(basename "$pkg")
  echo "  packages/$pkg_name..."
  (cd "$pkg" && flutter pub get)
done
echo -e "${GREEN}[3/6] Dependencies resolved (root + $(ls -d packages/*/ | wc -l) packages).${NC}"

# Step 4: Analysis (set -e safe via if/else; --no-fatal-infos matches CI)
echo -e "${YELLOW}[4/6] Running static analysis...${NC}"
if flutter analyze --no-fatal-infos; then
  echo -e "${GREEN}[4/6] Analysis clean — zero errors and warnings.${NC}"
else
  echo -e "${YELLOW}[4/6] Analysis found issues — see output above (non-fatal).${NC}"
fi

# Step 5: Tests — delegate to the disk-bounded monorepo runner so all
# 14 sibling packages plus the root app are exercised. Under set -e a
# non-zero exit aborts setup, which is correct: fresh-clone bring-up
# should fail loudly when the monorepo isn't green.
echo -e "${YELLOW}[5/6] Running tests (scripts/test_runner.sh)...${NC}"
TEST_START=$(date +%s)
./scripts/test_runner.sh
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
