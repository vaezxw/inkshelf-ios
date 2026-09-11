#!/usr/bin/env bash
# macOS only — mirrors Codemagic unsigned IPA packaging
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

brew list xcodegen &>/dev/null || brew install xcodegen
xcodegen generate

xcodebuild \
  -project InkShelf.xcodeproj \
  -scheme InkShelf \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

APP_PATH="$(find build/DerivedData/Build/Products -name 'InkShelf.app' -type d | head -n 1)"
test -n "$APP_PATH"
IPA_DIR="build/ipa"
rm -rf "$IPA_DIR"
mkdir -p "$IPA_DIR/Payload"
cp -R "$APP_PATH" "$IPA_DIR/Payload/"
(
  cd "$IPA_DIR"
  zip -qr InkShelf-unsigned.ipa Payload
  rm -rf Payload
)
ls -lah "$IPA_DIR/InkShelf-unsigned.ipa"
echo "Done. Install with Sideloadly."
