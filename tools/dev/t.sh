#!/bin/bash
# t.sh [-only-testing:…]：在自己的模拟器上跑测试，打印失败和总数。日志在 $OUT/test.log
source "$(dirname "$0")/common.sh"
cd "$IOS"
perl -e 'alarm 1800; exec @ARGV' xcodebuild -project CoinBounce.xcodeproj -scheme CoinBounce -destination "platform=iOS Simulator,id=$UD" -derivedDataPath "$DD" test "$@" > "$OUT/test.log" 2>&1
echo "EXIT $?"
grep -E "error:" "$OUT/test.log" | grep -v coretelephony | cut -c1-330 | sort -u | head -30
grep -E "Executed [0-9]+ tests" "$OUT/test.log" | tail -1
