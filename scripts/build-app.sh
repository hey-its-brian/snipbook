#!/usr/bin/env bash
# Builds Snipbook.app into ./build. Pass --install to copy it to /Applications.
set -euo pipefail

cd "$(dirname "$0")/.."
APP="build/Snipbook.app"

# SwiftUI macros need full Xcode; the Command Line Tools lack SwiftUI's macro plugin.
# Use Xcode even if xcode-select still points at the Command Line Tools.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

swift build -c release
BIN="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Snipbook" "$APP/Contents/MacOS/"
cp -R "$BIN/Highlightr_Highlightr.bundle" "$BIN/Snipbook_Snipbook.bundle" "$APP/Contents/Resources/"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Snipbook</string>
  <key>CFBundleDisplayName</key><string>Snipbook</string>
  <key>CFBundleIdentifier</key><string>com.heyitsbrian.snipbook</string>
  <key>CFBundleExecutable</key><string>Snipbook</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Sign with an Apple Development identity when there is one. macOS ties Accessibility permission
# (needed for Quick Search auto-paste) to the signature; an ad-hoc signature changes on every
# build, so the permission would have to be granted again after each rebuild.
IDENTITY="$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')"
if [[ -n "$IDENTITY" ]] && codesign --force --deep --sign "$IDENTITY" "$APP" 2>/dev/null; then
  echo "Signed with $IDENTITY"
else
  codesign --force --deep --sign - "$APP"
  echo "Signed ad hoc (Accessibility permission will need re-granting after each rebuild)"
fi
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  rm -rf /Applications/Snipbook.app
  cp -R "$APP" /Applications/
  echo "Installed to /Applications/Snipbook.app"
fi
