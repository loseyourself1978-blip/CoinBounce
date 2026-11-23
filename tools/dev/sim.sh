#!/bin/bash
# sim.sh [device type]：新建并启动一个自己的模拟器，UDID 记在 $OUT/udid
source "$(dirname "$0")/common.sh"
U=$(xcrun simctl create "CB-dev-$$" "${1:-iPhone 17}") && echo "$U" > "$OUT/udid${2:-}"
perl -e 'alarm 120; exec @ARGV' xcrun simctl boot "$U"
perl -e 'alarm 240; exec @ARGV' xcrun simctl bootstatus "$U" >/dev/null
echo "$U"
