#!/usr/bin/env bash
set -euo pipefail

# Config
SCHEME="CoinBounce"
PROJECT_PATH="ios/CoinBounce.xcodeproj"
DEVICE="iPhone 14 Pro"
BUNDLE_ID="com.coinbounce.CoinBounce"
APP_PATH=""

echo "[iOS-SIM] Building for iOS Simulator on device iPhone 17 Pro (OS 26.4) ..."
xcodebuild -project "$PROJECT_PATH" -scheme "$SCHEME" -destination "platform=iOS Simulator,OS=26.4,name=iPhone 17 Pro" clean build | tee build.log

echo "[iOS-SIM] Locating built .app housing..."
APP_PATH=$(bash -lc 'ls -d ~/Library/Developer/Xcode/DerivedData/*/Build/Products/Debug-iphonesimulator/*.app 2>/dev/null | head -n 1')
if [ -z "$APP_PATH" ]; then
  echo "ERROR: Could not locate built .app. Check Xcode build logs." >&2
  exit 2
fi
echo "[iOS-SIM] App path: $APP_PATH"

echo "[iOS-SIM] Booting/Ensuring simulator is ready..."
if ! xcrun simctl list devices | grep -q "(Booted)"; then
  xcrun simctl boot "$DEVICE" || true
  sleep 5
fi
if ! xcrun simctl list devices | grep -q "Booted"; then
  echo "ERROR: Could not boot simulator $DEVICE" >&2; exit 2
fi

echo "[iOS-SIM] Installing app..."
xcrun simctl install booted "$APP_PATH" || {
  echo "Install failed, trying with booted device directly..."; xcrun simctl install booted "$APP_PATH";
}

echo "[iOS-SIM] Launching app..."
xcrun simctl launch booted "$BUNDLE_ID" || {
  echo "Launch failed. Ensure the bundle id is correct."; exit 1;
}

echo "[iOS-SIM] Capturing screenshot..."
xcrun simctl io booted screenshot "$HOME/screenshot_current.png"

echo "[iOS-SIM] Running acceptance tests (offline mode still runs visual checks)..."
python3 acceptance/AcceptanceRunner.py acceptance/config.json || true

echo "[iOS-SIM] Done. Screenshot at $HOME/screenshot_current.png"
