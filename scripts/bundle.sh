#!/usr/bin/env bash
# Builds a release HorseTrainer.app in ./build (ad-hoc signed). Usage: scripts/bundle.sh
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP=build/HorseTrainer.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/HorseTrainer "$APP/Contents/MacOS/HorseTrainer"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Horse Trainer</string>
  <key>CFBundleDisplayName</key><string>Horse Trainer</string>
  <key>CFBundleIdentifier</key><string>com.nathanjiang.horsetrainer</string>
  <key>CFBundleExecutable</key><string>HorseTrainer</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.card-games</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP — open it with: open $APP"
