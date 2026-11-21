#!/bin/bash
# run.sh <名字> <等几秒> <截几张> <启动参数…>：装上、启动、截图到 $OUT/<名字>N.png
source "$(dirname "$0")/common.sh"
out=$1; wait=$2; shots=$3; shift 3
xcrun simctl terminate "$UD" $B >/dev/null 2>&1
perl -e 'alarm 60; exec @ARGV' xcrun simctl install "$UD" "$APP"
perl -e 'alarm 30; exec @ARGV' xcrun simctl launch "$UD" $B -debugSkipATT -debugSkipConsent -debugNoAds "$@" >/dev/null
sleep "$wait"
for i in $(seq 1 "$shots"); do perl -e 'alarm 20; exec @ARGV' xcrun simctl io "$UD" screenshot "$OUT/$out$i.png" >/dev/null 2>&1; sleep 0.7; done
xcrun simctl terminate "$UD" $B >/dev/null 2>&1
