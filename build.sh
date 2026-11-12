#!/bin/bash
# Build FilmReview.app into dist/. Uses project-local caches because the
# default SwiftPM caches may not be writable in sandboxed environments.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

CONFIG="${1:-release}"
if [[ "$CONFIG" != "debug" && "$CONFIG" != "release" ]]; then
  echo "usage: ./build.sh [debug|release]" >&2
  exit 2
fi

mkdir -p .build/modulecache .build/cache .build/config .build/security
# Swift uses sockets under TMPDIR. Keep that path short even in nested projects.
BUILD_TEMP="$(mktemp -d /private/tmp/filmreview-build.XXXXXX)"
trap 'rm -rf "$BUILD_TEMP"' EXIT
export TMPDIR="$BUILD_TEMP"
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/modulecache"

SWIFT_FLAGS=(
  --disable-sandbox
  --cache-path "$ROOT/.build/cache"
  --config-path "$ROOT/.build/config"
  --security-path "$ROOT/.build/security"
  -Xcc "-fmodules-cache-path=$ROOT/.build/modulecache"
  -Xswiftc -module-cache-path
  -Xswiftc "$ROOT/.build/modulecache"
)

if [[ "${FILMREVIEW_NO_DEBUG_INFO:-0}" == "1" ]]; then
  SWIFT_FLAGS+=(-debug-info-format none)
fi

echo "==> Building ($CONFIG)…"
swift build -c "$CONFIG" "${SWIFT_FLAGS[@]}"

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path "${SWIFT_FLAGS[@]}")"
APP="$ROOT/dist/FilmReview.app"

echo "==> Packaging $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/FilmReview" "$APP/Contents/MacOS/FilmReview"
cp "$ROOT/packaging/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
chmod +x "$APP/Contents/MacOS/FilmReview"

# Ad-hoc signature keeps macOS happy for local personal use.
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || true

echo "==> Done: $APP"
echo "    open \"$APP\""
