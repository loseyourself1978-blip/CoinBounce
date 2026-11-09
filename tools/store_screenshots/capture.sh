#!/bin/bash
# App Store screenshots (v11.7): capture candidate frames on a 6.9" simulator (iPhone 17 Pro Max, 1320×2868).
# usage: capture.sh <sim udid> <app path> <out dir> <scene> <lang: en|zh-Hans> [count] [interval]
# scenes: 1 machine/cascade (10 COIN) · 6 10-COIN drop from the top · 7 calm start screen ·
#         1 machine/cascade · 2 BONUS gate + spinning reels · 3 JACKPOT + progressive pool · 4 seven fruits + card pick · 5 BOSS K.O.
# Only DEBUG launch arguments that drive real game flows are used (autoplay coin drops, a realistic jackpot pool value,
# forcing the real jackpot / card-pick / K.O. paths); no debug overlays are drawn.
set -e
U=$1; APP=$2; OUT=$3; SCENE=$4; LANG_=$5; N=${6:-40}; DT=${7:-0.4}
BID=com.coinbounce.CoinBounce
mkdir -p "$OUT"
xcrun simctl status_bar "$U" override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
xcrun simctl install "$U" "$APP"
xcrun simctl terminate "$U" $BID 2>/dev/null || true
COMMON=(-AppleLanguages "($LANG_)" -AppleLocale "$([ "$LANG_" = en ] && echo en_US || echo zh_CN)" -debugSkipConsent -debugSkipATT -debugNoAds -debugSetCoins 2480)
case $SCENE in
  1) ARGS=(-autoplayBurst10); WAIT=25 ;;
  2) ARGS=(-autoplay); WAIT=12 ;;
  3) ARGS=(-autoplay -debugJackpotPool 12486.38 -debugJackpot); WAIT=6 ;;
  4) ARGS=(-shotCardPick); WAIT=6 ;;
  5) ARGS=(-autoplay -shotBossKO); WAIT=8 ;;
  6) ARGS=(-autoplayBurst10); WAIT=4 ;;      # CPP "Satisfying Physics": first 10-COIN batches pouring from the top
  7) ARGS=(); WAIT=5 ;;                       # CPP: calm start screen, nothing autoplaying
esac
xcrun simctl launch "$U" $BID "${COMMON[@]}" "${ARGS[@]}" >/dev/null
sleep $WAIT
for i in $(seq -w 1 $N); do
  xcrun simctl io "$U" screenshot "$OUT/s${SCENE}_${LANG_}_$i.png" >/dev/null 2>&1
  sleep "$DT"
done
xcrun simctl terminate "$U" $BID || true
