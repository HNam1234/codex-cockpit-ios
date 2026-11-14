#!/usr/bin/env bash
set -euo pipefail

: "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to the Apple Developer Team ID}"
BUNDLE_ID="${BUNDLE_ID:-vn.nam.CodexCockpit}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/.build/signed"

cd "$ROOT"
command -v xcodegen >/dev/null || brew install xcodegen
python3 scripts/generate_icon.py
xcodegen generate
rm -rf "$BUILD"
mkdir -p "$BUILD"

xcodebuild \
  -project CodexCockpit.xcodeproj \
  -scheme CodexCockpit \
  -configuration Release \
  -destination generic/platform=iOS \
  -archivePath "$BUILD/CodexCockpit.xcarchive" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates \
  archive

cat > "$BUILD/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>development</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>$DEVELOPMENT_TEAM</string>
  <key>stripSwiftSymbols</key><true/>
</dict></plist>
PLIST

xcodebuild \
  -exportArchive \
  -archivePath "$BUILD/CodexCockpit.xcarchive" \
  -exportPath "$BUILD/export" \
  -exportOptionsPlist "$BUILD/ExportOptions.plist" \
  -allowProvisioningUpdates

echo "Signed IPA is in: $BUILD/export/"
