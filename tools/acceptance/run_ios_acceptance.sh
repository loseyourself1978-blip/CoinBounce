#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

VERSION="$(python3 -c 'import json; print(json.load(open("PROJECT_VERSION.json","r",encoding="utf-8"))["version"])')"
COMMIT_SHA="$(git rev-parse HEAD 2>/dev/null || echo "")"

REPORT_DIR="$ROOT_DIR/reports/acceptance/ios/${VERSION}"
ART_DIR="$REPORT_DIR/artifacts"
mkdir -p "$ART_DIR"

echo "------------------------------------------------"
echo "CoinBounce iOS Acceptance"
echo "------------------------------------------------"
echo "Version: $VERSION"
echo "Commit:  $COMMIT_SHA"
echo "Report:  $REPORT_DIR"
echo ""

echo "[1/4] Build + unit tests"
./build_ios.sh

echo ""
echo "[2/4] Boot simulator (best effort)"
SIM_DEVICE_NAME="${SIM_DEVICE_NAME:-iPhone 17 Pro}"

set +e
xcrun simctl bootstatus booted -b >/dev/null 2>&1
if [ $? -ne 0 ]; then
  xcrun simctl boot "$SIM_DEVICE_NAME" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$SIM_DEVICE_NAME" -b >/dev/null 2>&1 || true
fi
set -e

echo ""
echo "[3/4] Install + launch + screenshot"
cd "$ROOT_DIR/ios"
xcodebuild -project CoinBounce.xcodeproj \
  -scheme CoinBounce \
  -sdk iphonesimulator \
  -destination "platform=iOS Simulator,name=${SIM_DEVICE_NAME}" \
  -derivedDataPath "$ROOT_DIR/ios/build" \
  build >/dev/null

APP_PATH="$ROOT_DIR/ios/build/Build/Products/Debug-iphonesimulator/CoinBounce.app"
if [ ! -d "$APP_PATH" ]; then
  echo "Expected app not found at: $APP_PATH"
  exit 1
fi

xcrun simctl install booted "$APP_PATH" >/dev/null
xcrun simctl launch booted com.coinbounce.CoinBounce >/dev/null
sleep 3

SCREENSHOT_PATH="$ART_DIR/screenshot.png"
xcrun simctl io booted screenshot "$SCREENSHOT_PATH" >/dev/null

echo ""
echo "[4/4] Compare to reference + render web report"
cd "$ROOT_DIR"

REF_IMG="$ROOT_DIR/samples/ref_400x880.png"
REGIONS="$ROOT_DIR/tools/acceptance/regions_ref400x880.json"
COMPARE_OUT="$ART_DIR/compare"
mkdir -p "$COMPARE_OUT"

COMPARE_JSON="$(python3 "$ROOT_DIR/tools/acceptance/compare_images.py" \
  --reference "$REF_IMG" \
  --candidate "$SCREENSHOT_PATH" \
  --regions "$REGIONS" \
  --out "$COMPARE_OUT")"

REPORT_HTML="$REPORT_DIR/index.html"
python3 "$ROOT_DIR/tools/acceptance/render_report.py" \
  --compare_json "$COMPARE_JSON" \
  --out_html "$REPORT_HTML" \
  --title "CoinBounce iOS 验收报告" \
  --version "$VERSION" \
  --commit "$COMMIT_SHA"

echo ""
echo "✅ Acceptance report generated:"
echo "$REPORT_HTML"

if command -v open >/dev/null 2>&1; then
  open "$REPORT_HTML" || true
fi

