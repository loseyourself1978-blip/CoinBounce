#!/bin/bash
# perf.sh <name> <seconds> [launch args…]：在模拟器上跑推币机 -autoplayLite，记下每秒的 PUSHER_STATS / MAIN_STATS，打印平均帧率和金币数
source "$(dirname "$0")/common.sh"
name=$1; secs=$2; shift 2
xcrun simctl terminate "$UD" $B >/dev/null 2>&1
perl -e 'alarm 60; exec @ARGV' xcrun simctl install "$UD" "$APP"
xcrun simctl launch --console-pty --terminate-running-process "$UD" $B -debugSkipATT -debugSkipConsent -debugNoAds -startPusher -autoplayLite "$@" > "$OUT/$name.log" 2>&1 &
P=$!
sleep "$secs"
kill $P 2>/dev/null; xcrun simctl terminate "$UD" $B >/dev/null 2>&1
python3 - "$OUT/$name.log" <<'PY'
import re,sys
t=open(sys.argv[1],errors='ignore').read()
f=[float(x) for x in re.findall(r'MAIN_STATS fps=([\d.]+)',t)]
p=re.findall(r'PUSHER_STATS fps=([\d.]+) total=(\d+)',t)
def avg(a): return sum(a)/len(a) if a else 0
tail=f[10:] if len(f)>12 else f
print(f"main fps avg {avg(tail):.1f} min {min(tail) if tail else 0:.1f} (n={len(tail)}); pusher fps avg {avg([float(a) for a,_ in p[10:]]):.1f}; coins last {p[-1][1] if p else '-'}")
PY
