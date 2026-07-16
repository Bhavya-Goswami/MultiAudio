#!/bin/zsh
# Build MultiAudio and package it as a runnable .app bundle.
# Usage: ./Scripts/package-app.sh [debug|release]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-release}"
# Normalize: accept "debug" / "release" or SPM's -c values
case "$CONFIG" in
  debug|Debug) CONFIG="debug" ;;
  release|Release) CONFIG="release" ;;
  *)
    echo "usage: $0 [debug|release]" >&2
    exit 1
    ;;
esac

APP_NAME="MultiAudio"
APP_DIR="$ROOT/dist/${APP_NAME}.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
INFO_PLIST="$ROOT/Sources/MultiAudio/Resources/Info.plist"

if [[ ! -f "$INFO_PLIST" ]]; then
  echo "error: missing Info.plist at $INFO_PLIST" >&2
  exit 1
fi

if ! command -v swift >/dev/null 2>&1; then
  echo "error: swift not found. Install Xcode or run: xcode-select --install" >&2
  exit 1
fi

echo "→ Building $APP_NAME ($CONFIG)…"
swift build -c "$CONFIG"

# SPM may place the binary at .build/<config>/Name or .build/<triple>/<config>/Name
BIN=""
CANDIDATES=(
  "$ROOT/.build/$CONFIG/$APP_NAME"
  "$ROOT/.build/arm64-apple-macosx/$CONFIG/$APP_NAME"
  "$ROOT/.build/x86_64-apple-macosx/$CONFIG/$APP_NAME"
)
for candidate in "${CANDIDATES[@]}"; do
  if [[ -x "$candidate" ]]; then
    BIN="$candidate"
    break
  fi
done

if [[ -z "$BIN" ]]; then
  BIN="$(find "$ROOT/.build" -type f -name "$APP_NAME" -perm +111 2>/dev/null | head -1 || true)"
fi

if [[ -z "${BIN:-}" || ! -x "$BIN" ]]; then
  echo "error: could not find built binary for $APP_NAME" >&2
  echo "looked under $ROOT/.build" >&2
  exit 1
fi

echo "→ Packaging $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"
cp "$BIN" "$MACOS/$APP_NAME"
cp "$INFO_PLIST" "$CONTENTS/Info.plist"
chmod +x "$MACOS/$APP_NAME"

# Ad-hoc sign so the app launches cleanly for local / CI builds
if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || true
fi

echo "✓ Built: $APP_DIR"
echo "  Run with: open \"$APP_DIR\""
