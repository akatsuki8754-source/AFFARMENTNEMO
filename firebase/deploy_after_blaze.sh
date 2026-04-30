#!/bin/bash
#
# Blaze アップグレード完了後にこのスクリプトを実行すると、Phase 3 (Gemini 本接続) が一発で動く。
#
# 🔒 セキュリティ: API キーはコマンドライン引数で渡さない (shell history / ps 出力に残る)。
#                 必ずファイル経由で渡す。
#
# 前提:
#   1. Firebase コンソールで Blaze プランへアップグレード済み
#      → https://console.firebase.google.com/project/kotodama-86a14/usage/details
#   2. Google AI Studio で API キー取得済み (制限: generativelanguage.googleapis.com のみ)
#      → https://aistudio.google.com/app/apikey
#   3. 取得したキーを一時ファイルに保存
#      → 例: echo -n "AIza..." > /tmp/gemini_key.txt && chmod 600 /tmp/gemini_key.txt
#
# 実行:
#   bash deploy_after_blaze.sh /tmp/gemini_key.txt
#

set -e

KEY_FILE="${1:-}"

if [ -z "$KEY_FILE" ] || [ ! -f "$KEY_FILE" ]; then
    cat <<USAGE
Usage: bash deploy_after_blaze.sh <KEY_FILE>

  KEY_FILE: API キーの中身だけが入ったファイル (改行なし、権限600推奨)
  例:
    echo -n "AIza..." > /tmp/gemini_key.txt
    chmod 600 /tmp/gemini_key.txt
    bash deploy_after_blaze.sh /tmp/gemini_key.txt
    rm /tmp/gemini_key.txt   # 完了後に必ず削除

API キー取得: https://aistudio.google.com/app/apikey
  (kotodama プロジェクトで作成し、generativelanguage.googleapis.com に制限すること)
USAGE
    exit 1
fi

PROJECT="kotodama-86a14"

echo "🔐 1/4 GEMINI_API_KEY を Secret Manager に登録中..."
firebase functions:secrets:set GEMINI_API_KEY \
    --project="$PROJECT" --data-file="$KEY_FILE"

echo "⚙️  2/4 Functions の .env を設定..."
cat > "$(dirname "$0")/functions/.env.${PROJECT}" <<EOF
AI_GENERATION_ENABLED=true
AI_MAX_USER_DAILY=5
AI_MAX_GLOBAL_DAILY=800
AI_MAX_GLOBAL_PER_MINUTE=25
AI_GEMINI_MODEL=gemini-2.5-flash-lite
POST_MAX_USER_DAILY=30
POST_MAX_GLOBAL_DAILY=1000
REACTION_MAX_USER_DAILY=200
REPORT_MAX_USER_DAILY=30
EOF

echo "🚀 3/4 Cloud Functions を deploy 中..."
cd "$(dirname "$0")/functions"
npm install --silent
cd ..
firebase deploy --only functions --project="$PROJECT" --force

echo "🎯 4/4 Firestore system/aiRuntime.clientEnabled = true (Firebase CLI access token 経由)"
TOKEN=$(node -e "console.log(JSON.parse(require('fs').readFileSync(require('os').homedir()+'/.config/configstore/firebase-tools.json','utf8')).tokens.access_token)")
curl -s -X PATCH \
    "https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/system/aiRuntime?updateMask.fieldPaths=clientEnabled" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"fields": {"clientEnabled": {"booleanValue": true}}}' >/dev/null
unset TOKEN
echo "   ✅ aiRuntime.clientEnabled = true"

echo ""
echo "🎉 完了。アプリ側で AI 短冊ウィザードを起動すると Gemini Flash-Lite が呼ばれます。"
echo "   ・1日の上限: ユーザー5回 / グローバル800回 (Gemini無料枠1500RPDの半分)"
echo "   ・分間レート: API側で30RPM (Cloud Functions maxInstances=3 × concurrency=10)"
echo "   ・予算: \$5/月 (アラート 50%/90%/100%/150%)"
echo "   ・緊急停止: system/aiBudgetAlert.monthlyEmergencyStop = true で即停止"
echo ""
echo "🧹 セキュリティ: KEY_FILE を必ず削除してください:"
echo "   rm $KEY_FILE"
