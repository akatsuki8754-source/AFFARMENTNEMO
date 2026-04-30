#!/bin/bash
#
# Blaze アップグレード完了後にこのスクリプトを実行すると、Phase 3 (Gemini 本接続) が一発で動く。
#
# 前提:
#   1. Firebase コンソールで Blaze プランへアップグレード済み
#      → https://console.firebase.google.com/project/kotodama-86a14/usage/details
#   2. Google AI Studio で API キー取得済み
#      → https://aistudio.google.com/app/apikey
#
# 実行:
#   bash deploy_after_blaze.sh <GEMINI_API_KEY>
#

set -e

if [ -z "$1" ]; then
    echo "Usage: bash deploy_after_blaze.sh <GEMINI_API_KEY>"
    echo ""
    echo "API キーは https://aistudio.google.com/app/apikey で取得"
    exit 1
fi

API_KEY="$1"
PROJECT="kotodama-86a14"

echo "🔐 1/4 GEMINI_API_KEY を Secret Manager に登録中..."
echo "$API_KEY" | firebase functions:secrets:set GEMINI_API_KEY \
    --project="$PROJECT" --data-file=-

echo "⚙️  2/4 Functions params (AI_GENERATION_ENABLED=true) を設定..."
firebase functions:params:set AI_GENERATION_ENABLED=true --project="$PROJECT" 2>/dev/null || \
    echo "AI_GENERATION_ENABLED=true" > "$(dirname "$0")/functions/.env.kotodama-86a14"

echo "🚀 3/4 Cloud Functions を deploy 中..."
cd "$(dirname "$0")/functions"
npm install
firebase deploy --only functions --project="$PROJECT"

echo "🎯 4/4 Firestore system/aiRuntime.clientEnabled を true に切替..."
node <<EOF
const admin = require('firebase-admin');
admin.initializeApp({ projectId: '$PROJECT' });
const db = admin.firestore();
(async () => {
  await db.doc('system/aiRuntime').set({
    clientEnabled: true,
    reason: 'Phase 3: Gemini 本接続有効化',
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  console.log('✅ system/aiRuntime.clientEnabled = true');
  process.exit(0);
})();
EOF

echo ""
echo "🎉 完了。アプリ側で AI 短冊ウィザードを起動すると Gemini Flash-Lite が呼ばれます。"
echo "   ・1日の上限: ユーザー5回 / グローバル800回 (無料枠 1500 RPD 内に余裕)"
echo "   ・予算超過時の緊急停止: system/aiBudgetAlert.monthlyEmergencyStop = true で停止"
