#!/bin/bash
# 归档 Release 构建并上传到 App Store Connect（TestFlight）。
# 版本号（CFBundleShortVersionString）用工程里的 MARKETING_VERSION（1.0.0）；
# 构建号自动递增：用当前时间 YYYYMMDDHHMM（只增不减，App Store Connect 要求同一版本下构建号递增）。
# 用 Xcode 里登录的 Apple 账号签名、上传（-allowProvisioningUpdates）。
set -euo pipefail
cd "$(dirname "$0")/../ios"
OUT="${OUT:-$HOME/Downloads/CoinBounce_资料归档/tmp.noindex/testflight}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
mkdir -p "$OUT"
echo "build number $BUILD_NUMBER"
xcodebuild -scheme CoinBounce -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$OUT/CoinBounce.xcarchive" -allowProvisioningUpdates \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" archive
xcodebuild -exportArchive -archivePath "$OUT/CoinBounce.xcarchive" \
  -exportOptionsPlist "$(pwd)/../scripts/ExportOptions-AppStore.plist" \
  -exportPath "$OUT/export" -allowProvisioningUpdates
