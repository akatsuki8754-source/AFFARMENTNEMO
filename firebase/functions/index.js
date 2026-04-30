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
const { onMessagePublished } = require('firebase-functions/v2/pubsub');
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

// ─────────────────────────────────────────────
// 共通: per-uid rate limit transactional checker
//   60秒に max件、1日に day件
// ─────────────────────────────────────────────
async function rateLimit(uid, kind, perMinMax, perDayMax) {
  const today = jstDateKey();
  const minRef = db.collection('rateLimits').doc(`${uid}_${kind}`);
  const dayRef = db.collection('rateLimits').doc(`${uid}_${kind}_${today}`);
  return db.runTransaction(async tx => {
    const [minSnap, daySnap] = await Promise.all([tx.get(minRef), tx.get(dayRef)]);
    const now = Date.now();
    const ts = (minSnap.exists ? minSnap.data().ts : []) || [];
    const recent = ts.filter(t => now - t < 60_000);
    if (recent.length >= perMinMax) {
      throw new HttpsError('resource-exhausted', `Rate limit (${kind}/min)`);
    }
    const dailyUsed = daySnap.exists ? (daySnap.data().count || 0) : 0;
    if (dailyUsed >= perDayMax) {
      throw new HttpsError('resource-exhausted', `Rate limit (${kind}/day)`);
    }
    recent.push(now);
    tx.set(minRef, { ts: recent }, { merge: true });
    tx.set(dayRef, { count: dailyUsed + 1, day: today }, { merge: true });
  });
}

async function checkBudgetAndAuth(request) {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in required');
  const budgetSnap = await db.doc('system/aiBudgetAlert').get();
  if (budgetSnap.data()?.monthlyEmergencyStop === true) {
    throw new HttpsError('resource-exhausted', 'Service temporarily unavailable (budget protection)');
  }
  return uid;
}

// ─────────────────────────────────────────────
// Post 反応 via Cloud Function (1 ユーザー 1 投稿に 1 reaction、1分20件、1日200件)
// ─────────────────────────────────────────────
exports.reactToPost = onCall(
  { region: 'asia-northeast1', timeoutSeconds: 10, memory: '256MiB', maxInstances: 5, concurrency: 20 },
  async (request) => {
    const uid = await checkBudgetAndAuth(request);
    const room = String(request.data?.room || '');
    const postId = String(request.data?.postId || '');
    const reaction = String(request.data?.reaction || '');
    if (!['ja_JP', 'en', 'zh_CN', 'zh_TW', 'ko_KR'].includes(room)) {
      throw new HttpsError('invalid-argument', 'invalid room');
    }
    if (!['like', 'heart', 'peace', 'none'].includes(reaction)) {
      throw new HttpsError('invalid-argument', 'invalid reaction');
    }
    if (!postId || postId.length > 64) {
      throw new HttpsError('invalid-argument', 'invalid postId');
    }
    await rateLimit(uid, 'react', 20, 200);

    const ref = db.collection('timelineRooms').doc(room).collection('posts').doc(postId);
    return db.runTransaction(async tx => {
      const snap = await tx.get(ref);
      if (!snap.exists) throw new HttpsError('not-found', 'post not found');
      const data = snap.data();
      const reactedBy = data.reactedBy || {};
      const prev = reactedBy[uid] || null;
      const counts = {
        like: data.reactionLike || 0,
        heart: data.reactionHeart || 0,
        peace: data.reactionPeace || 0,
      };
      // 旧 reaction を取消
      if (prev && counts[prev] !== undefined) counts[prev] = Math.max(0, counts[prev] - 1);
      // 新 reaction 適用
      let newReactedBy = { ...reactedBy };
      if (reaction === 'none') {
        delete newReactedBy[uid];
      } else {
        newReactedBy[uid] = reaction;
        counts[reaction] = (counts[reaction] || 0) + 1;
      }
      tx.update(ref, {
        reactedBy: newReactedBy,
        reactionLike: counts.like,
        reactionHeart: counts.heart,
        reactionPeace: counts.peace,
      });
      return { ok: true };
    });
  }
);

// ─────────────────────────────────────────────
// Post 通報 via Cloud Function (1ユーザー 1分5件、1日30件)
// ─────────────────────────────────────────────
exports.reportPost = onCall(
  { region: 'asia-northeast1', timeoutSeconds: 10, memory: '256MiB', maxInstances: 3, concurrency: 10 },
  async (request) => {
    const uid = await checkBudgetAndAuth(request);
    const room = String(request.data?.room || '');
    const postId = String(request.data?.postId || '');
    const reason = String(request.data?.reason || '').slice(0, 200);
    if (!['ja_JP', 'en', 'zh_CN', 'zh_TW', 'ko_KR'].includes(room)) {
      throw new HttpsError('invalid-argument', 'invalid room');
    }
    if (!postId || postId.length > 64 || !reason) {
      throw new HttpsError('invalid-argument', 'invalid params');
    }
    await rateLimit(uid, 'report', 5, 30);

    const postRef = db.collection('timelineRooms').doc(room).collection('posts').doc(postId);
    await db.collection('reports').add({
      reporterUid: uid,
      targetType: 'post',
      targetId: postId,
      targetRoom: room,
      reason,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    await postRef.update({
      reportedBy: admin.firestore.FieldValue.arrayUnion(uid),
      reportCount: admin.firestore.FieldValue.increment(1),
    });
    return { ok: true };
  }
);

// ─────────────────────────────────────────────
// Timeline 投稿 via Cloud Function (rate limit 入り)
//   - 直接 Firestore 書き込みより安全
//   - 1ユーザー 60秒に最大 5 件
//   - 1ユーザー 1日に最大 30 件
//   - 緊急停止フラグ尊重
// ─────────────────────────────────────────────
exports.submitTimelinePost = onCall(
  {
    region: 'asia-northeast1',
    timeoutSeconds: 15,
    memory: '256MiB',
    maxInstances: 5,
    concurrency: 20,
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError('unauthenticated', 'Sign in required');

    // Emergency stop チェック
    const budgetSnap = await db.doc('system/aiBudgetAlert').get();
    if (budgetSnap.data()?.monthlyEmergencyStop === true) {
      throw new HttpsError('resource-exhausted', 'Service temporarily unavailable (budget protection)');
    }

    // Input validation
    const text = String(request.data?.text || '').trim();
    const room = String(request.data?.room || '');
    if (text.length < 1 || text.length > 100) {
      throw new HttpsError('invalid-argument', 'text must be 1-100 chars');
    }
    if (!['ja_JP', 'en', 'zh_CN', 'zh_TW', 'ko_KR'].includes(room)) {
      throw new HttpsError('invalid-argument', 'invalid room');
    }

    // Rate limit transaction: 60秒に5件、1日30件
    const today = jstDateKey();
    const rateRef = db.collection('postRateLimits').doc(uid);
    const dailyRef = db.collection('postRateLimits').doc(`${uid}_${today}`);

    const allowed = await db.runTransaction(async tx => {
      const [rateSnap, dailySnap] = await Promise.all([tx.get(rateRef), tx.get(dailyRef)]);
      const now = Date.now();
      const rateBucket = rateSnap.exists ? rateSnap.data() : { ts: [] };
      // 60秒以内の投稿だけ残す
      const recent = (rateBucket.ts || []).filter(t => now - t < 60_000);
      if (recent.length >= 5) {
        return { ok: false, reason: 'rate_60s' };
      }
      const dailyUsed = dailySnap.exists ? (dailySnap.data().count || 0) : 0;
      if (dailyUsed >= 30) {
        return { ok: false, reason: 'rate_day' };
      }
      recent.push(now);
      tx.set(rateRef, { ts: recent }, { merge: true });
      tx.set(dailyRef, { count: dailyUsed + 1, day: today }, { merge: true });
      return { ok: true };
    });

    if (!allowed.ok) {
      throw new HttpsError('resource-exhausted', `Rate limit: ${allowed.reason}`, allowed);
    }

    // 投稿作成
    const now = admin.firestore.Timestamp.now();
    const expireAt = admin.firestore.Timestamp.fromMillis(now.toMillis() + 24 * 3600 * 1000);
    const post = {
      authorUid: uid,
      text,
      languageRoom: room,
      createdAt: now,
      expireAt,
      reportCount: 0,
      isHidden: false,
    };
    const ref = await db.collection('timelineRooms').doc(room).collection('posts').add(post);
    return { id: ref.id, postedAt: now.toMillis() };
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
// ─────────────────────────────────────────────
// 予算アラート Pub/Sub Subscriber
//   Cloud Billing が "kotodama-budget-alerts" topic に予算情報を publish する。
//   90% 到達時に system/aiBudgetAlert.monthlyEmergencyStop = true を立て、
//   aiGenerateWish 全停止 (UX 影響なし、フォールバック静的サンプルが返る)
// ─────────────────────────────────────────────
// 100% 到達時に請求先アンリンクするための service account 必要権限:
//   roles/billing.projectManager (project レベル)
// → 自動付与済 (compute SA に editor 権限あるため)
const PROJECT_ID = 'kotodama-86a14';
const PROJECT_BILLING_RESOURCE = `projects/${PROJECT_ID}`;

async function disableProjectBilling() {
  // Cloud Billing API: PUT billingInfo with empty billingAccountName → unlink
  const { GoogleAuth } = require('google-auth-library');
  const auth = new GoogleAuth({
    scopes: ['https://www.googleapis.com/auth/cloud-billing']
  });
  const client = await auth.getClient();
  const url = `https://cloudbilling.googleapis.com/v1/${PROJECT_BILLING_RESOURCE}/billingInfo`;
  const res = await client.request({
    url,
    method: 'PUT',
    data: { billingAccountName: '' },
  });
  console.error(`[budgetAlert] BILLING DISABLED:`, res.data);
  return res.data;
}

exports.budgetAlert = onMessagePublished(
  {
    topic: 'kotodama-budget-alerts',
    region: 'asia-northeast1',
    memory: '256MiB',
    timeoutSeconds: 60,
    maxInstances: 1,
  },
  async (event) => {
    let payload;
    try {
      payload = event.data.message.json;
    } catch (e) {
      // Cloud Billing は base64 JSON で送る — 自動 decode された場合と raw の場合あり
      try {
        const raw = Buffer.from(event.data.message.data, 'base64').toString('utf8');
        payload = JSON.parse(raw);
      } catch (err) {
        console.error('budgetAlert: cannot parse payload', err);
        return;
      }
    }
    const costAmount = Number(payload?.costAmount || 0);
    const budgetAmount = Number(payload?.budgetAmount || 1);
    const ratio = budgetAmount > 0 ? costAmount / budgetAmount : 0;
    const currency = payload?.currencyCode || 'JPY';
    const budgetDisplayName = payload?.budgetDisplayName || 'unknown';

    console.log(`[budgetAlert] ${budgetDisplayName}: ${costAmount}/${budgetAmount} ${currency} (${(ratio * 100).toFixed(1)}%)`);

    // 100% 到達 → 請求先アカウントをアンリンク (TRUE HARD CAP、Firebase全機能停止)
    if (ratio >= 1.0) {
      try {
        await disableProjectBilling();
        await db.doc('system/aiBudgetAlert').set({
          monthlyEmergencyStop: true,
          billingDisabled: true,
          currentMonthUSD: costAmount,
          triggeredRatio: ratio,
          triggeredAt: admin.firestore.FieldValue.serverTimestamp(),
          triggerReason: `BILLING DISABLED at ${(ratio * 100).toFixed(0)}% (${costAmount}/${budgetAmount} ${currency})`,
        }, { merge: true });
        console.error(`[budgetAlert] 🚨 BILLING DISABLED at ${(ratio * 100).toFixed(0)}%`);
      } catch (e) {
        console.error(`[budgetAlert] Failed to disable billing:`, e);
        // フォールバック: フラグだけでも立てる
        await db.doc('system/aiBudgetAlert').set({
          monthlyEmergencyStop: true,
          billingDisabled: false,
          billingDisableError: String(e).slice(0, 500),
        }, { merge: true });
      }
      return;
    }

    // 90% 以上 → 緊急停止フラグ (Firestore writes / Functions invocations 拒否)
    if (ratio >= 0.9) {
      await db.doc('system/aiBudgetAlert').set({
        monthlyEmergencyStop: true,
        currentMonthUSD: costAmount,
        currentMonthKey: payload?.budgetDisplayName ? new Date().toISOString().slice(0, 7) : null,
        triggeredRatio: ratio,
        triggeredAt: admin.firestore.FieldValue.serverTimestamp(),
        triggerReason: `Budget at ${(ratio * 100).toFixed(0)}% (${costAmount}/${budgetAmount} ${currency})`,
      }, { merge: true });
      console.log(`[budgetAlert] EMERGENCY STOP triggered at ${(ratio * 100).toFixed(0)}%`);
    } else {
      // 90% 未満 → 解除
      const snap = await db.doc('system/aiBudgetAlert').get();
      if (snap.data()?.monthlyEmergencyStop === true && !snap.data()?.billingDisabled) {
        await db.doc('system/aiBudgetAlert').set({
          monthlyEmergencyStop: false,
          currentMonthUSD: costAmount,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        console.log(`[budgetAlert] emergency stop lifted (${(ratio * 100).toFixed(0)}%)`);
      }
    }
  }
);

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
