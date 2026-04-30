/**
 * Firebase Cloud Functions for コトダマ
 *
 * 機能:
 *  - aiGenerateWish: Gemini API を使った AI 短冊生成 (Phase 3 — 要 Blaze プラン)
 *  - cleanupExpiredPosts: 24h 以上経過した posts を削除 (毎時実行)
 *  - sakuraSeeder: 100件未満の言語ルームに擬似投稿を追加 (15分毎)
 *
 * デプロイ:
 *   cd firebase/functions
 *   npm install firebase-functions firebase-admin @google/generative-ai
 *   firebase deploy --only functions --project kotodama-86a14
 *
 * 必要な Secret:
 *   firebase functions:secrets:set GEMINI_API_KEY
 *
 * 注意:
 *   このファイルは Phase 3 デプロイ用のスタブ。
 *   Blaze プラン未契約のため、現状はクライアント側 (KnowledgeMap.swift) で
 *   静的サンプルを返している。
 */

const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();

const geminiApiKey = defineSecret('GEMINI_API_KEY');

// ─────────────────────────────────────────────
// AI 短冊生成 (Gemini Flash-Lite)
// ─────────────────────────────────────────────
exports.aiGenerateWish = onCall(
  { secrets: [geminiApiKey], region: 'asia-northeast1' },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError('unauthenticated', 'Sign in required');

    // 個人クォータチェック (1日5回)
    const today = new Date().toISOString().slice(0, 10);
    const quotaRef = db.collection('userQuotas').doc(`${uid}_${today}`);
    const quotaSnap = await quotaRef.get();
    const used = quotaSnap.exists ? (quotaSnap.data().count || 0) : 0;
    if (used >= 5) {
      throw new HttpsError('resource-exhausted', 'Daily AI quota exceeded');
    }

    // グローバルクォータチェック (1日800)
    const globalRef = db.collection('globalQuota').doc(today);
    const globalSnap = await globalRef.get();
    const globalUsed = globalSnap.exists ? (globalSnap.data().count || 0) : 0;
    if (globalUsed >= 800) {
      throw new HttpsError('resource-exhausted', 'Global AI capacity full');
    }

    const path = request.data.path; // [{title, prompt}, ...]
    const prompt = buildPrompt(path);

    // Gemini API 呼び出し
    const { GoogleGenerativeAI } = require('@google/generative-ai');
    const genAI = new GoogleGenerativeAI(geminiApiKey.value());
    const model = genAI.getGenerativeModel({ model: 'gemini-2.5-flash-lite' });

    let candidates = [];
    try {
      const result = await model.generateContent(prompt);
      const text = result.response.text();
      candidates = parseCandidates(text);
    } catch (err) {
      console.error('Gemini error:', err);
      // フォールバック: テンプレ
      candidates = fallbackCandidates(path);
    }

    // クォータ更新
    await quotaRef.set({ count: used + 1, updatedAt: Date.now() }, { merge: true });
    await globalRef.set({ count: globalUsed + 1, updatedAt: Date.now() }, { merge: true });

    return { candidates };
  }
);

function buildPrompt(path) {
  const titles = path.map(p => p.title).join(' > ');
  return `あなたは自己肯定感を育てる短い「願いの言葉」を作るアシスタントです。
ユーザーの状況: ${titles}

以下の3つの異なるアプローチで、それぞれ80文字以内の言葉を1つずつ作ってください。番号付きリストで出力。
1. 自己肯定型 (Self-Affirmation Theory): 「私は◯◯」で始まる断定的でない、価値観を肯定する文
2. If-Thenプラン型 (Implementation Intentions): 「もし◯◯したら、◯◯する」の形
3. 価値観型 (Mental Contrasting): 障害を予期しつつ前向きに進む文

出力形式:
1. <80文字以内>
2. <80文字以内>
3. <80文字以内>`;
}

function parseCandidates(text) {
  const lines = text.split('\n').map(l => l.trim()).filter(l => l);
  const candidates = [];
  for (const line of lines) {
    const m = line.match(/^\d+[.)]\s*(.+)$/);
    if (m) candidates.push(m[1].slice(0, 200));
    if (candidates.length >= 3) break;
  }
  return candidates.length === 3 ? candidates : fallbackCandidates([]);
}

function fallbackCandidates(path) {
  return [
    '私は今日も小さな一歩を踏み出せる人だ。',
    'もし迷ったら、深呼吸してから次の選択をする。',
    '進む方向は揺らいでも、私は私の歩幅で歩める。',
  ];
}

// ─────────────────────────────────────────────
// 24h 以上経過した posts を削除 (毎時)
// ─────────────────────────────────────────────
exports.cleanupExpiredPosts = onSchedule(
  { schedule: 'every 60 minutes', region: 'asia-northeast1' },
  async () => {
    const now = admin.firestore.Timestamp.now();
    const rooms = ['ja_JP', 'en', 'zh_CN', 'zh_TW', 'ko_KR'];
    let totalDeleted = 0;

    for (const room of rooms) {
      const expired = await db
        .collection('timelineRooms').doc(room).collection('posts')
        .where('expireAt', '<', now)
        .limit(500)
        .get();
      const batch = db.batch();
      expired.docs.forEach(doc => batch.delete(doc.ref));
      if (expired.size > 0) {
        await batch.commit();
        totalDeleted += expired.size;
      }
    }
    console.log(`[cleanup] deleted ${totalDeleted} expired posts`);
  }
);

// ─────────────────────────────────────────────
// サクラ自動投稿 (Phase 3 拡張用、現状は無効化)
// ─────────────────────────────────────────────
exports.sakuraSeeder = onSchedule(
  { schedule: 'every 15 minutes', region: 'asia-northeast1' },
  async () => {
    // クライアント側で既にサンプル表示しているため、サーバー側はオプション
    // Phase 3 で運用方針確定後に有効化
    console.log('[sakuraSeeder] disabled in current phase');
  }
);
