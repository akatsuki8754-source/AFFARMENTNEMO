#!/bin/bash
#
# シミュレータで App を起動し、6枚のスクショを撮影する。
# 前提: スクショモード ON (kotodama.screenshot.mode = YES)
#       AdMob バナー非表示、ステータスバー 09:41 整形済み
#
# 使い方: bash tools/capture_screenshots.sh <DEVICE_UDID>
#

set -e

DEVICE="${1:-DDC6270A-4198-4D9D-ACBE-2C831856FA6E}"  # iPhone 17 Pro Max
APP_BUNDLE="com.mendoi.AFFARMENTNEMO"
OUT="$(dirname "$0")/screenshots"
APP_PATH="$HOME/Library/Developer/Xcode/DerivedData/AFFARMENTNEMO-fmxlczpgwjwnpqcfadjnfhgsfznh/Build/Products/Debug-iphonesimulator/AFFARMENTNEMO.app"

echo "🚀 device=$DEVICE"

# シミュレータ起動
xcrun simctl boot "$DEVICE" 2>/dev/null || true
open -a Simulator

# ステータスバー整形 (09:41 / フル電波 / フルバッテリー / WiFi)
xcrun simctl status_bar "$DEVICE" override \
    --time "9:41" \
    --batteryState charged --batteryLevel 100 \
    --cellularMode active --cellularBars 4 \
    --wifiMode active --wifiBars 3 \
    --dataNetwork wifi

# スクショモード ON
xcrun simctl spawn "$DEVICE" defaults write "$APP_BUNDLE" kotodama.screenshot.mode -bool YES

# アプリインストール (既存ビルドを使う)
if [ -d "$APP_PATH" ]; then
    xcrun simctl install "$DEVICE" "$APP_PATH"
    xcrun simctl launch "$DEVICE" "$APP_BUNDLE" >/dev/null 2>&1 || true
    sleep 3
else
    echo "⚠️  App not built at $APP_PATH"
    exit 1
fi

mkdir -p "$OUT"

shoot() {
    local name="$1"
    echo "📸 $name"
    xcrun simctl io "$DEVICE" screenshot "$OUT/$name"
    sleep 1
}

# 1. ホーム画面 (スプラッシュ後の状態)
sleep 2
shoot "01_home.png"

# 残りはユーザー操作が必要なので、placeholder は撮らずに案内のみ
echo ""
echo "✅ 1枚目撮影完了: $OUT/01_home.png"
echo "次は手動で以下の画面を撮影してください (スクショモードは ON のまま):"
echo "  2. みんなの願いタブ → 02_timeline.png"
echo "  3. 言葉を追加 > AIに3択で考えてもらう (3択画面) → 03_ai_select.png"
echo "  4. AI候補3個表示 (チェック2つ入れた状態) → 04_ai_candidates.png"
echo "  5. 設定 > 言語切替 → 05_lang.png"
echo "  6. ホーム > 録音中 → 06_recording.png"
echo ""
echo "撮影は xcrun simctl io $DEVICE screenshot $OUT/<name>.png"
