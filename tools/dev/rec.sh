#!/bin/bash
# rec.sh <out.mp4> <先等几秒> <录几秒> <启动参数…>：装上、启动、录屏到 $OUT/<out.mp4>（用 SIGINT 停，别用别的信号）
source "$(dirname "$0")/common.sh"
out=$1; pre=$2; secs=$3; shift 3
xcrun simctl terminate "$UD" $B >/dev/null 2>&1
perl -e 'alarm 60; exec @ARGV' xcrun simctl install "$UD" "$APP"
perl -e 'alarm 30; exec @ARGV' xcrun simctl launch "$UD" $B -debugSkipATT -debugSkipConsent -debugNoAds "$@" >/dev/null
sleep "$pre"
xcrun simctl io "$UD" recordVideo --codec h264 --force "$OUT/$out" >/dev/null 2>&1 &
R=$!
sleep "$secs"
kill -INT $R; wait $R 2>/dev/null
xcrun simctl terminate "$UD" $B >/dev/null 2>&1
ls -la "$OUT/$out" | awk '{print $5}'
