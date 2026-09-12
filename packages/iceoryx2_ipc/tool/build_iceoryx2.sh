#!/usr/bin/env bash
# Build libiceoryx2_ffi_c.so from Eclipse iceoryx2 at a PINNED commit.
#
# Author: rust-systems-engineer (RSE), 2026-09-12.
#
# WHY A SHA AND NOT A VERSION
# ---------------------------
# Measured on the built library, 2026-09-12, x86_64:
#
#     nm -D --defined-only libiceoryx2_ffi_c.so | grep -iE 'version|abi|revision|semver'
#     -> (empty)   across 660 exported iox2_* symbols
#
# THERE IS NO VERSION SYMBOL. The library cannot be asked what it is at
# runtime, so a stale or mismatched .so is UNDETECTABLE at dlopen time. The
# only pin that exists is the source commit, which is why this script pins a
# SHA and records it, and why road_friction_source.dart carries the same SHA
# as a written claim rather than a checked one. An honest absence beats a
# check that cannot fire.
#
# WHY A BUILD DIR AND NOT VENDORING
# ---------------------------------
# A full iceoryx2 checkout plus its cargo target dir is ~2.2 GB. This clones
# shallow (--depth 1 at the exact SHA) OUTSIDE the repository. Nothing from
# upstream is committed here.
#
# IDEMPOTENT: re-running with the build already at the pinned SHA re-prints the
# path and sha256 without refetching or rebuilding.
set -euo pipefail

readonly ICEORYX2_SHA="05a3a8fa59b87af5ced3af12f9145d4f46de472b"
readonly ICEORYX2_URL="${SNGNAV_ICEORYX2_URL:-https://github.com/eclipse-iceoryx/iceoryx2.git}"
readonly BUILD_DIR="${SNGNAV_ICEORYX2_BUILD_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/sngnav/iceoryx2}"
readonly PROFILE="${SNGNAV_ICEORYX2_PROFILE:-release}"
readonly SRC_DIR="$BUILD_DIR/src"

log() { printf '[build_iceoryx2] %s\n' "$*" >&2; }
die() { printf '[build_iceoryx2] FATAL: %s\n' "$*" >&2; exit 1; }

command -v git   >/dev/null || die "git not found"
command -v cargo >/dev/null || die "cargo not found (install a Rust toolchain)"

# --- fetch the pinned commit, shallow, without a full clone -----------------
if [ -d "$SRC_DIR/.git" ] && [ "$(git -C "$SRC_DIR" rev-parse HEAD 2>/dev/null || true)" = "$ICEORYX2_SHA" ]; then
  log "source already at pinned SHA ${ICEORYX2_SHA:0:12} — not refetching"
else
  log "fetching iceoryx2 @ ${ICEORYX2_SHA:0:12} (shallow) into $SRC_DIR"
  mkdir -p "$SRC_DIR"
  git -C "$SRC_DIR" rev-parse --git-dir >/dev/null 2>&1 || git -C "$SRC_DIR" init -q
  git -C "$SRC_DIR" remote remove origin >/dev/null 2>&1 || true
  git -C "$SRC_DIR" remote add origin "$ICEORYX2_URL"
  # A bare-SHA fetch. Verified against github.com 2026-09-12; if a mirror
  # refuses `allowReachableSHA1InWant`, set SNGNAV_ICEORYX2_URL to a local clone.
  git -C "$SRC_DIR" fetch --depth 1 origin "$ICEORYX2_SHA"
  git -C "$SRC_DIR" checkout -q --detach FETCH_HEAD
fi

# The pin is only a pin if it is VERIFIED after checkout, not assumed from the
# fetch exiting 0.
actual="$(git -C "$SRC_DIR" rev-parse HEAD)"
[ "$actual" = "$ICEORYX2_SHA" ] || die "checkout is at $actual, expected $ICEORYX2_SHA"
log "source verified at $actual"

# --- build the C FFI cdylib -------------------------------------------------
# crate `iceoryx2-ffi-c` declares crate-type = ["rlib", "cdylib", "staticlib"];
# the cdylib is libiceoryx2_ffi_c.so. Its build script also emits the cbindgen
# header used by native/road_friction_publisher.c.
log "cargo build --profile=$PROFILE -p iceoryx2-ffi-c"
if [ "$PROFILE" = "release" ]; then
  ( cd "$SRC_DIR" && CARGO_TARGET_DIR="$BUILD_DIR/target" cargo build --release -p iceoryx2-ffi-c )
else
  ( cd "$SRC_DIR" && CARGO_TARGET_DIR="$BUILD_DIR/target" cargo build --profile "$PROFILE" -p iceoryx2-ffi-c )
fi

SO="$BUILD_DIR/target/$PROFILE/libiceoryx2_ffi_c.so"
[ -f "$SO" ] || die "expected $SO after a successful build, and it is not there"

# The generated header, located rather than guessed at: its parent directory
# name carries a cargo build hash that changes between builds.
HDR="$(find "$BUILD_DIR/target/$PROFILE" -path '*iceoryx2-ffi-c-cbindgen/include/iox2/iceoryx2.h' -print -quit 2>/dev/null || true)"
[ -n "$HDR" ] || die "cbindgen header not found under $BUILD_DIR/target/$PROFILE"
INCLUDE_DIR="${HDR%/iox2/iceoryx2.h}"

sha="$(sha256sum "$SO" | cut -d' ' -f1)"

cat <<EOF
ICEORYX2_SHA=$ICEORYX2_SHA
ICEORYX2_SRC=$SRC_DIR
ICEORYX2_LIB=$SO
ICEORYX2_LIB_SHA256=$sha
ICEORYX2_INCLUDE_DIR=$INCLUDE_DIR
ICEORYX2_PROFILE=$PROFILE
EOF
