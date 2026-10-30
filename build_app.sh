#!/bin/bash
# Builds "Land of Ezerian 2.app" (release) into ./build.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Land of Ezerian 2.app"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/Ezerian"

rm -rf "$APP" build/AppIcon.iconset
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/AppIcon.iconset
cp "$BIN" "$APP/Contents/MacOS/Ezerian"
cp -R Resources/Portraits "$APP/Contents/Resources/Portraits"

# App icon, drawn by the game itself from its own art.
"$BIN" --icon build/icon-1024.png > /dev/null
for size in 16 32 128 256 512; do
  sips -z $size $size build/icon-1024.png --out "build/AppIcon.iconset/icon_${size}x${size}.png" > /dev/null
  sips -z $((size * 2)) $((size * 2)) build/icon-1024.png --out "build/AppIcon.iconset/icon_${size}x${size}@2x.png" > /dev/null
done
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Ezerian 2</string>
  <key>CFBundleDisplayName</key><string>The Land of Ezerian 2</string>
  <key>CFBundleIdentifier</key><string>com.ezerian.landofezerian2</string>
  <key>CFBundleExecutable</key><string>Ezerian</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.2</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.role-playing-games</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" > /dev/null 2>&1 || true
echo "Built $APP"
