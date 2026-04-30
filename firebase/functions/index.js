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
 * 必要な Secret / Params:
 *   firebase functions:secrets:set GEMINI_API_KEY
 *   firebase functions:config:set ai.enabled=true ではなく、v2 param AI_GENERATION_ENABLED=true を使う
 *
 * 注意:
 *   このファイルは Phase 3 デプロイ用のスタブ。
 *   Blaze プラン未契約のため、現状はクライアント側 (KnowledgeMap.swift) で
 *   静的サンプルを返している。
 */

const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { defineSecret, defineString, defineInt } = require('firebase-functions/params');
const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();

const geminiApiKey = defineSecret('GEMINI_API_KEY');
const aiGenerationEnabled = defineString('AI_GENERATION_ENABLED', { default: 'false' });
const maxUserDaily = defineInt('AI_MAX_USER_DAILY', { default: 5 });
const maxGlobalDaily = defineInt('AI_MAX_GLOBAL_DAILY', { default: 800 });
const aiModelName = defineString('AI_GEMINI_MODEL', { default: 'gemini-2.5-flash-lite' });

// ─────────────────────────────────────────────
// AI 短冊生成 (Gemini Flash-Lite)
// ─────────────────────────────────────────────
exports.aiGenerateWish = onCall(
  {
    secrets: [geminiApiKey],
    region: 'asia-northeast1',
    timeoutSeconds: 30,
    minInstances: 0,
    maxInstances: 3,            // 同時 3 インスタンス上限 (Gemini 30RPM 内)
    concurrency: 10,            // 1インスタンスあたり 10 並列まで
    memory: '256MiB',           // メモリ最小 (コスト削減)
    cpu: 1,
    enforceAppCheck: false,     // App Check は将来有効化 (移行時に true へ)
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError('unauthenticated', 'Sign in required');
    if (aiGenerationEnabled.value() !== 'true') {
      throw new HttpsError('failed-precondition', 'AI generation disabled');
    }

    const budgetSnap = await db.doc('system/aiBudgetAlert').get();
    if (budgetSnap.data()?.monthlyEmergencyStop === true) {
      throw new HttpsError('resource-exhausted', 'AI budget emergency stop');
    }

    const path = validatePath(request.data?.path);
    const prompt = buildPrompt(path);
    // 日付キーは JST (UTC+9) で計算 (日本ユーザー向け、リセットは深夜0時)
    const today = jstDateKey();
    const quotaRef = db.collection('userQuotas').doc(`${uid}_${today}`);
    const globalRef = db.collection('globalQuota').doc(today);

    const reservation = await reserveQuota({
      uid,
      quotaRef,
      globalRef,
      maxUser: maxUserDaily.value(),
      maxGlobal: maxGlobalDaily.value(),
    });

    try {
      const { GoogleGenerativeAI } = require('@google/generative-ai');
      const genAI = new GoogleGenerativeAI(geminiApiKey.value());
      const model = genAI.getGenerativeModel({
        model: aiModelName.value(),
        generationConfig: {
          responseMimeType: 'application/json',
          temperature: 0.8,
          maxOutputTokens: 512,
        },
      });
      const result = await model.generateContent(prompt);
      const text = result.response.text();
      const candidates = parseCandidates(text);
      await logAIUsage(uid, path, candidates, false);
      return {
        candidates,
        quotaRemaining: reservation.userRemaining,
        fallback: false,
      };
    } catch (err) {
      console.error('Gemini error:', err);
      // ロールバック失敗時もフォールバック候補は返す (UX 優先)
      try { await rollbackQuota({ quotaRef, globalRef }); }
      catch (rbErr) { console.error('rollback failed:', rbErr); }
      const candidates = fallbackCandidates(path);
      try { await logAIUsage(uid, path, candidates, true); }
      catch (logErr) { console.error('log failed:', logErr); }
      return {
        candidates,
        quotaRemaining: reservation.userRemaining + 1,
        fallback: true,
      };
    }
  }
);

function buildPrompt(path) {
  const titles = path.map(p => p.title).join(' > ');
  return `あなたは自己肯定感を育てる短い「願いの言葉」を作るアシスタントです。
ユーザーの状況: ${titles}

以下の3つの異なるアプローチで、それぞれ80文字以内の言葉を1つずつ作ってください。
すべて「〜したい」「〜でいたい」「〜になりたい」の願い形で統一してください。
有名人や名言がテーマの場合も、既存の名言を引用せず、考え方だけを参考にしたオリジナル文にしてください。
1. 自己肯定型 (Self-Affirmation Theory): 価値観を肯定する文
2. If-Thenプラン型 (Implementation Intentions): 「もし◯◯したら、◯◯したい」の形
3. 価値観型 (Mental Contrasting): 障害を予期しつつ前向きに進む文

出力形式:
JSONのみ。コードブロックや説明文は不要。
{
  "candidates": [
    {"type": "self_affirmation", "text": "<80文字以内>"},
    {"type": "if_then", "text": "<80文字以内>"},
    {"type": "values", "text": "<80文字以内>"}
  ]
}`;
}

function parseCandidates(text) {
  const cleaned = text
    .trim()
    .replace(/^```json\s*/i, '')
    .replace(/^```\s*/i, '')
    .replace(/```$/i, '')
    .trim();
  try {
    const parsed = JSON.parse(cleaned);
    const items = Array.isArray(parsed.candidates) ? parsed.candidates : [];
    const candidates = items
      .map(item => normalizeCandidate(String(item.text ?? item)))
      .filter(Boolean)
      .slice(0, 3);
    if (candidates.length === 3) return candidates;
  } catch (_) {
    // below: tolerate numbered-list model drift
  }
  const lines = cleaned.split('\n').map(line => line.trim()).filter(Boolean);
  const candidates = lines
    .map(line => line.match(/^\d+[.)]\s*(.+)$/)?.[1])
    .filter(Boolean)
    .map(normalizeCandidate)
    .slice(0, 3);
  if (candidates.length === 3) return candidates;
  throw new Error(`AI response parse failed: ${cleaned.slice(0, 200)}`);
}

function fallbackCandidates(path) {
  const selected = path.map(p => p.title).filter(Boolean).slice(-1)[0] || '今日の一歩';
  return [
    normalizeCandidate(`${selected}に向けて、今日も小さな一歩を踏み出したい。`),
    normalizeCandidate(`もし迷ったら、深呼吸してから${selected}に戻りたい。`),
    normalizeCandidate(`進む方向が揺れても、自分の歩幅で${selected}を大切にしたい。`),
  ];
}

function normalizeCandidate(raw) {
  const trimmed = raw.trim().replace(/^["'「『]|["'」』]$/g, '').slice(0, 100);
  if (!trimmed) return '';
  if (/(したい|でいたい|になりたい|たい)[。.!！]?$/.test(trimmed)) {
    return /[。.!！]$/.test(trimmed) ? trimmed : `${trimmed}。`;
  }
  return `${trimmed.replace(/[。.!！]+$/, '')}したい。`;
}

function validatePath(path) {
  if (!Array.isArray(path) || path.length === 0 || path.length > 8) {
    throw new HttpsError('invalid-argument', 'Invalid path');
  }
  return path.map(item => {
    const title = String(item?.title ?? '').trim().slice(0, 80);
    const prompt = String(item?.prompt ?? '').trim().slice(0, 200);
    if (!title) throw new HttpsError('invalid-argument', 'Invalid path title');
    return { title, prompt };
  });
}

async function reserveQuota({ uid, quotaRef, globalRef, maxUser, maxGlobal }) {
  return db.runTransaction(async tx => {
    const [quotaSnap, globalSnap] = await Promise.all([tx.get(quotaRef), tx.get(globalRef)]);
    const userUsed = quotaSnap.exists ? (quotaSnap.data().count || 0) : 0;
    const globalUsed = globalSnap.exists ? (globalSnap.data().count || 0) : 0;
    if (globalUsed >= maxGlobal) {
      throw new HttpsError('resource-exhausted', 'Daily global quota exceeded', {
        reason: 'global_quota',
      });
    }
    if (userUsed >= maxUser) {
      throw new HttpsError('resource-exhausted', 'Daily user quota exceeded', {
        reason: 'user_quota',
        canWatchAd: (quotaSnap.data()?.adWatchCountToday || 0) < 2,
      });
    }
    const now = admin.firestore.FieldValue.serverTimestamp();
    tx.set(quotaRef, {
      uid,
      count: userUsed + 1,
      updatedAt: now,
      dateKey: quotaRef.id.split('_').pop(),
    }, { merge: true });
    tx.set(globalRef, {
      count: globalUsed + 1,
      updatedAt: now,
    }, { merge: true });
    return { userRemaining: Math.max(0, maxUser - userUsed - 1) };
  });
}

async function rollbackQuota({ quotaRef, globalRef }) {
  await db.runTransaction(async tx => {
    const [quotaSnap, globalSnap] = await Promise.all([tx.get(quotaRef), tx.get(globalRef)]);
    const userUsed = quotaSnap.exists ? (quotaSnap.data().count || 0) : 0;
    const globalUsed = globalSnap.exists ? (globalSnap.data().count || 0) : 0;
    tx.set(quotaRef, {
      count: Math.max(0, userUsed - 1),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    tx.set(globalRef, {
      count: Math.max(0, globalUsed - 1),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  });
}

/// JST (UTC+9) で YYYY-MM-DD 形式の日付キーを返す
function jstDateKey() {
  const now = new Date();
  // JST = UTC + 9h
  const jstMs = now.getTime() + 9 * 60 * 60 * 1000;
  return new Date(jstMs).toISOString().slice(0, 10);
}

async function logAIUsage(uid, path, candidates, fallback) {
  await db.collection('aiUsageLogs').add({
    uid,
    path,
    candidates,
    fallback,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

// ─────────────────────────────────────────────
// 24h 以上経過した posts を削除 (毎時)
// ─────────────────────────────────────────────
exports.cleanupExpiredPosts = onSchedule(
  {
    schedule: 'every 60 minutes',
    region: 'asia-northeast1',
    memory: '256MiB',
    timeoutSeconds: 60,
    maxInstances: 1,
  },
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
  {
    // クライアント側で既にサンプル表示しているため、サーバー側はオプション
    // 現状は1日1回のno-op (コスト最小) — Phase 3 で運用方針確定後に頻度上げる
    schedule: 'every 1440 minutes',
    region: 'asia-northeast1',
    memory: '256MiB',
    timeoutSeconds: 30,
    maxInstances: 1,
  },
  async () => {
    console.log('[sakuraSeeder] disabled in current phase');
  }
);
