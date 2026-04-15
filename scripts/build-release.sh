#!/bin/bash
set -euo pipefail

VERSION="${1:-0.1.0}"
SIGNING_IDENTITY="Developer ID Application: Readwise, Inc (QV36BMA4LN)"
APP="Kuro's Wiki.app"
DMG="KurosWiki-macOS.dmg"

echo "=== Building Kuro's Wiki v${VERSION} ==="

# 1. Build universal binary (arm64 + x86_64)
echo "[1/6] Building arm64..."
swift build -c release --arch arm64
echo "[1/6] Building x86_64..."
swift build -c release --arch x86_64

# 2. Assemble .app bundle
echo "[2/6] Creating app bundle..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

lipo -create \
  .build/arm64-apple-macosx/release/KurosWiki \
  .build/x86_64-apple-macosx/release/KurosWiki \
  -output "$APP/Contents/MacOS/KurosWiki"

cp -R .build/arm64-apple-macosx/release/KurosWiki_KurosWiki.bundle "$APP/Contents/Resources/"
cp -R .build/arm64-apple-macosx/release/SwiftTerm_SwiftTerm.bundle "$APP/Contents/Resources/"
cp .build/arm64-apple-macosx/release/KurosWiki_KurosWiki.bundle/KurosWiki.icns "$APP/Contents/Resources/KurosWiki.icns"

cat > "$APP/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Kuro's Wiki</string>
    <key>CFBundleDisplayName</key><string>Kuro's Wiki</string>
    <key>CFBundleIdentifier</key><string>com.kuroswiki.app</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleExecutable</key><string>KurosWiki</string>
    <key>CFBundleIconFile</key><string>KurosWiki</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# 3. Code sign
echo "[3/6] Signing..."
codesign --deep --force --options runtime --sign "$SIGNING_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"

# 4. Create DMG with drag-to-Applications
echo "[4/6] Creating DMG..."
rm -f "$DMG"
create-dmg \
  --volname "Kuro's Wiki" \
  --window-pos 200 120 \
  --window-size 660 400 \
  --icon-size 160 \
  --icon "Kuro's Wiki.app" 160 190 \
  --app-drop-link 500 190 \
  --hide-extension "Kuro's Wiki.app" \
  --no-internet-enable \
  "$DMG" \
  "$APP"

codesign --sign "$SIGNING_IDENTITY" "$DMG"

# 5. Notarize
echo "[5/6] Notarizing..."
xcrun notarytool submit "$DMG" --keychain-profile "notarytool" --wait

# 6. Staple
echo "[6/6] Stapling..."
xcrun stapler staple "$DMG"

echo ""
echo "=== Done: $DMG ($(du -h "$DMG" | cut -f1)) ==="
echo "Universal binary (arm64 + x86_64), signed, notarized, stapled."
echo ""
echo "To publish:"
echo "  gh release create v${VERSION} ${DMG} --title \"Kuro's Wiki v${VERSION}\" --notes \"...\""
