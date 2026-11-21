# 开发脚本共用的设置。OUT = 放日志和截图的目录（默认 /tmp/coinbounce-dev），UD = 模拟器 UDID（默认读 $OUT/udid）
IOS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../ios" && pwd)"
OUT="${OUT:-/tmp/coinbounce-dev}"; mkdir -p "$OUT"
DD="$HOME/Library/Developer/Xcode/DerivedData/CoinBounce-polish"
APP="$DD/Build/Products/Debug-iphonesimulator/CoinBounce.app"
B=com.coinbounce.CoinBounce
UD="${UD:-$(cat "$OUT/udid" 2>/dev/null)}"
