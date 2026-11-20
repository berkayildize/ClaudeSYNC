#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ClaudeSYNC"
BUNDLE_ID="com.claudesync.app"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
BUILD_NUM="$(git -C "$ROOT_DIR" rev-list --count HEAD 2>/dev/null || echo 1)"

DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "==> Building $APP_NAME release binary..."
cd "$ROOT_DIR"
swift build -c release

BIN_PATH="$ROOT_DIR/.build/release/$APP_NAME"
if [[ ! -x "$BIN_PATH" ]]; then
  echo "Error: compiled binary not found at $BIN_PATH" >&2
  exit 1
fi

echo "==> Assembling $APP_NAME.app..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BIN_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

# Generate AppIcon.icns
TMP_ICONSET="$(mktemp -d)/AppIcon.iconset"
swift "$ROOT_DIR/scripts/generate-icon.swift" "$TMP_ICONSET"
iconutil -c icns "$TMP_ICONSET" -o "$RESOURCES_DIR/AppIcon.icns"
rm -rf "$(dirname "$TMP_ICONSET")"

cat > "$CONTENTS_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUM}</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "==> Ad-hoc signing bundle..."
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
echo "==> Built: $APP_DIR"

for arg in "$@"; do
  case "$arg" in
    --install)
      INSTALL_PATH="/Applications/$APP_NAME.app"
      echo "==> Installing to $INSTALL_PATH..."
      rm -rf "$INSTALL_PATH"
      cp -R "$APP_DIR" "$INSTALL_PATH"
      echo "==> Installed: $INSTALL_PATH"
      ;;
    --dmg)
      DMG_PATH="$DIST_DIR/${APP_NAME}-v${VERSION}-macOS.dmg"
      STAGE_DIR="$(mktemp -d)"
      cp -R "$APP_DIR" "$STAGE_DIR/"
      ln -s /Applications "$STAGE_DIR/Applications"
      rm -f "$DMG_PATH"
      echo "==> Creating DMG: $DMG_PATH..."
      hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE_DIR" -ov -format UDZO "$DMG_PATH" >/dev/null
      rm -rf "$STAGE_DIR"
      echo "==> Created DMG: $DMG_PATH"
      ;;
    --relaunch)
      echo "==> Relaunching /Applications/$APP_NAME.app (v$VERSION)..."
      pkill -x "$APP_NAME" 2>/dev/null || true
      sleep 0.5
      open -a "/Applications/$APP_NAME.app"
      ;;
  esac
done
