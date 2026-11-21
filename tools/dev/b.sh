#!/bin/bash
# b.sh：编译模拟器版，只打印错误
source "$(dirname "$0")/common.sh"
cd "$IOS"
perl -e 'alarm 900; exec @ARGV' xcodebuild -project CoinBounce.xcodeproj -scheme CoinBounce -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath "$DD" build > "$OUT/build.log" 2>&1
echo "EXIT $?"
grep -E "error:" "$OUT/build.log" | sort -u | cut -c1-300 | head -30
