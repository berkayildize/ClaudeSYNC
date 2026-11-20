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
    <key>NSHumanReadableCopyright</key>
    <string>© 2026 @berkayildize · MIT Open Source</string>
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
      RW_DMG="$(mktemp -u /tmp/${APP_NAME}-rw-XXXXXX).dmg"
      STAGE_DIR="$(mktemp -d)"
      BG_DIR="$STAGE_DIR/.background"
      mkdir -p "$BG_DIR"

      cp -R "$APP_DIR" "$STAGE_DIR/"
      ln -s /Applications "$STAGE_DIR/Applications"

      echo "==> Generating Retina DMG installer background (v${VERSION})..."
      BG_1X="$(mktemp -u /tmp/${APP_NAME}-bg1x-XXXXXX).png"
      BG_2X="$(mktemp -u /tmp/${APP_NAME}-bg2x-XXXXXX).png"
      swift "$ROOT_DIR/scripts/generate-dmg-bg.swift" "$BG_1X" "$BG_2X" "$VERSION"
      tiffutil -cathidpicheck "$BG_1X" "$BG_2X" -out "$BG_DIR/background.tiff" >/dev/null
      rm -f "$BG_1X" "$BG_2X"

      # Ensure no previously mounted ClaudeSYNC volume collides
      if [[ -d "/Volumes/$APP_NAME" ]]; then
        hdiutil detach "/Volumes/$APP_NAME" -force >/dev/null 2>&1 || true
      fi

      rm -f "$RW_DMG" "$DMG_PATH"
      echo "==> Creating writable DMG image for Finder layout..."
      hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE_DIR" -fs HFS+ -fsargs "-c c=64,a=16,e=16" -format UDRW -size 32m "$RW_DMG" >/dev/null
      rm -rf "$STAGE_DIR"

      MOUNT_OUT="$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG")"
      MOUNT_DEV="$(echo "$MOUNT_OUT" | awk '/\/Volumes\// {print $1; exit}' | tr -d '\r')"
      MOUNT_POINT="$(echo "$MOUNT_OUT" | sed -n 's/^.*\(\/Volumes\/.*\)$/\1/p' | head -n 1 | tr -d '\r' | sed 's/[[:space:]]*$//')"
      VOL_NAME="$(basename "$MOUNT_POINT")"

      echo "==> Applying Finder DMG window layout (660x420 Retina)..."
      osascript <<APPLESCRIPT
set bgAlias to (POSIX file "${MOUNT_POINT}/.background/background.tiff") as alias
tell application "Finder"
  tell disk "$VOL_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {180, 120, 840, 568}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 108
    set text size of viewOptions to 13
    set background picture of viewOptions to bgAlias
    set position of item "${APP_NAME}.app" of container window to {180, 206}
    set position of item "Applications" of container window to {480, 206}
    update without registering applications
    delay 1.8
    close
    open
    delay 0.8
    close
  end tell
end tell
APPLESCRIPT

      # Set custom volume icon & hide internal files AFTER Finder has written .DS_Store
      cp "$RESOURCES_DIR/AppIcon.icns" "$MOUNT_POINT/.VolumeIcon.icns"
      if command -v SetFile >/dev/null 2>&1; then
        SetFile -a C "$MOUNT_POINT" 2>/dev/null || true
      fi
      chflags hidden "$MOUNT_POINT/.background" "$MOUNT_POINT/.VolumeIcon.icns" 2>/dev/null || true

      sync
      sleep 1
      hdiutil detach "$MOUNT_DEV" >/dev/null 2>&1 || hdiutil detach "$MOUNT_POINT" -force >/dev/null 2>&1 || true

      echo "==> Compressing final DMG: $DMG_PATH..."
      hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" >/dev/null
      rm -f "$RW_DMG"
      echo "==> Created styled DMG: $DMG_PATH"
      ;;
    --relaunch)
      echo "==> Relaunching /Applications/$APP_NAME.app (v$VERSION)..."
      pkill -x "$APP_NAME" 2>/dev/null || true
      sleep 0.5
      open -a "/Applications/$APP_NAME.app"
      ;;
  esac
done
