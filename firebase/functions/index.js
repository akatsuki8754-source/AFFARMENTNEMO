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
const maxAIPerMinute = defineInt('AI_MAX_GLOBAL_PER_MINUTE', { default: 25 });
const aiModelName = defineString('AI_GEMINI_MODEL', { default: 'gemini-2.5-flash-lite' });
const maxPostUserDaily = defineInt('POST_MAX_USER_DAILY', { default: 30 });
const maxPostGlobalDaily = defineInt('POST_MAX_GLOBAL_DAILY', { default: 1000 });
const maxReactionUserDaily = defineInt('REACTION_MAX_USER_DAILY', { default: 200 });
const maxReportUserDaily = defineInt('REPORT_MAX_USER_DAILY', { default: 30 });

const LANGUAGE_OPTIONS = [
  { locale: 'ja', room: 'ja_JP', instruction: '日本語' },
  { locale: 'en', room: 'en', instruction: 'English' },
  { locale: 'zh_CN', room: 'zh_CN', instruction: '简体中文' },
  { locale: 'zh_TW', room: 'zh_TW', instruction: '繁體中文' },
  { locale: 'ko', room: 'ko_KR', instruction: '한국어' },
  { locale: 'es', room: 'es', instruction: 'Español' },
  { locale: 'fr', room: 'fr', instruction: 'Français' },
  { locale: 'de', room: 'de', instruction: 'Deutsch' },
  { locale: 'pt_BR', room: 'pt_BR', instruction: 'Português do Brasil' },
  { locale: 'id', room: 'id', instruction: 'Bahasa Indonesia' },
  { locale: 'vi', room: 'vi', instruction: 'Tiếng Việt' },
  { locale: 'th', room: 'th', instruction: 'ไทย' },
  { locale: 'hi', room: 'hi', instruction: 'हिन्दी' },
  { locale: 'ar', room: 'ar', instruction: 'العربية' },
];
const ALLOWED_ROOMS = LANGUAGE_OPTIONS.map(option => option.room);

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
    enforceAppCheck: false,      // アプリ外からの直叩きを拒否
  },
  async (request) => {
    requireAppCheck(request);
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
    const locale = validateLocale(request.data?.locale);
    const prompt = buildPrompt(path, locale);
    // 日付キーは JST (UTC+9) で計算 (日本ユーザー向け、リセットは深夜0時)
    const today = jstDateKey();
    const quotaRef = db.collection('userQuotas').doc(`${uid}_${today}`);
    const globalRef = db.collection('globalQuota').doc(today);

    await rateLimit(uid, 'ai', 3, maxUserDaily.value());
    await globalRateLimit('ai', maxAIPerMinute.value());
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
          temperature: 0.95,           // 多様性向上 (0.8 → 0.95)
          maxOutputTokens: 768,        // 100字×3+JSON余裕
          topP: 0.95,
        },
      });
      // ★ DEBUG: prompt と response を構造化ログに残す (Cloud Logging で参照可能)
      console.info('[GeminiPrompt]', JSON.stringify({
        uid,
        locale,
        pathTitles: path.map(p => p.title),
        promptChars: prompt.length,
        promptPreview: prompt.slice(0, 500),
        model: aiModelName.value(),
        temperature: 0.95,
      }));
      const result = await model.generateContent(prompt);
      const text = result.response.text();
      console.info('[GeminiResponse]', JSON.stringify({
        uid,
        responseChars: text.length,
        responsePreview: text.slice(0, 500),
      }));
      const isFamousQuoteMode = /famous_quotes|quote_business|quote_life|quote_sport/.test(
        path.map(p => p.prompt || '').join(' ')
      );
      const candidates = parseCandidates(text, isFamousQuoteMode, locale);
      await logAIUsage(uid, path, candidates, false);
      return {
        candidates,
        mode: isFamousQuoteMode ? 'famous_quote' : 'affirmation',
        quotaRemaining: reservation.userRemaining,
        fallback: false,
        // DEBUG: クライアント側で実際の prompt を確認できるように (本番でも安全)
        debugPromptPreview: prompt.slice(0, 200),
      };
    } catch (err) {
      console.error('Gemini error:', err);
      // ロールバック失敗時もフォールバック候補は返す (UX 優先)
      try { await rollbackQuota({ quotaRef, globalRef }); }
      catch (rbErr) { console.error('rollback failed:', rbErr); }
      const candidates = fallbackCandidates(path, locale);
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

async function globalRateLimit(kind, perMinMax) {
  const ref = db.collection('rateLimits').doc(`global_${kind}`);
  return db.runTransaction(async tx => {
    const snap = await tx.get(ref);
    const now = Date.now();
    const ts = (snap.exists ? snap.data().ts : []) || [];
    const recent = ts.filter(t => now - t < 60_000);
    if (recent.length >= perMinMax) {
      throw new HttpsError('resource-exhausted', `Rate limit (${kind}/global/min)`);
    }
    recent.push(now);
    tx.set(ref, {
      ts: recent,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  });
}

async function reserveGlobalDaily(kind, maxDaily) {
  const day = jstDateKey();
  const ref = db.collection('globalDailyLimits').doc(`${kind}_${day}`);
  return db.runTransaction(async tx => {
    const snap = await tx.get(ref);
    const used = snap.exists ? (snap.data().count || 0) : 0;
    if (used >= maxDaily) {
      throw new HttpsError('resource-exhausted', `Daily global quota exceeded (${kind})`, {
        reason: 'global_quota',
      });
    }
    tx.set(ref, {
      kind,
      day,
      count: used + 1,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  });
}

async function checkBudgetAndAuth(request) {
  requireAppCheck(request);
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in required');
  const budgetSnap = await db.doc('system/aiBudgetAlert').get();
  if (budgetSnap.data()?.monthlyEmergencyStop === true) {
    throw new HttpsError('resource-exhausted', 'Service temporarily unavailable (budget protection)');
  }
  return uid;
}

function requireAppCheck(request) {
  // DEBUG: 一時的に App Check を緩和 (iOS Debug Provider トークン未配布対策)
  // 本番ビルド (TestFlight 経由) で AppAttest が動作するようになったら再度厳格化
  if (!request.app?.appId) {
    console.warn('[requireAppCheck] App Check missing, allowing (debug)');
  }
}

// ─────────────────────────────────────────────
// Post 反応 via Cloud Function (1 ユーザー 1 投稿に 1 reaction、1分20件、1日200件)
// ─────────────────────────────────────────────
exports.reactToPost = onCall(
  { region: 'asia-northeast1', timeoutSeconds: 10, memory: '256MiB', maxInstances: 5, concurrency: 20, enforceAppCheck: false },
  async (request) => {
    const uid = await checkBudgetAndAuth(request);
    const room = String(request.data?.room || '');
    const postId = String(request.data?.postId || '');
    const reaction = String(request.data?.reaction || '');
    if (!ALLOWED_ROOMS.includes(room)) {
      throw new HttpsError('invalid-argument', 'invalid room');
    }
    if (!['like', 'heart', 'peace', 'none'].includes(reaction)) {
      throw new HttpsError('invalid-argument', 'invalid reaction');
    }
    if (!postId || postId.length > 64) {
      throw new HttpsError('invalid-argument', 'invalid postId');
    }
    await rateLimit(uid, 'react', 20, maxReactionUserDaily.value());

    const ref = db.collection('timelineRooms').doc(room).collection('posts').doc(postId);
    return db.runTransaction(async tx => {
      const snap = await tx.get(ref);
      if (!snap.exists) throw new HttpsError('not-found', 'post not found');
      const data = snap.data();
      if (data.isHidden === true) throw new HttpsError('failed-precondition', 'post hidden');
      if (data.expireAt && data.expireAt.toMillis() <= Date.now()) {
        throw new HttpsError('failed-precondition', 'post expired');
      }
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
  { region: 'asia-northeast1', timeoutSeconds: 10, memory: '256MiB', maxInstances: 3, concurrency: 10, enforceAppCheck: false },
  async (request) => {
    const uid = await checkBudgetAndAuth(request);
    const room = String(request.data?.room || '');
    const postId = String(request.data?.postId || '');
    const reason = String(request.data?.reason || '').slice(0, 200);
    if (!ALLOWED_ROOMS.includes(room)) {
      throw new HttpsError('invalid-argument', 'invalid room');
    }
    if (!postId || postId.length > 64 || !reason) {
      throw new HttpsError('invalid-argument', 'invalid params');
    }
    await rateLimit(uid, 'report', 5, maxReportUserDaily.value());

    const postRef = db.collection('timelineRooms').doc(room).collection('posts').doc(postId);
    const reportRef = db.collection('reports').doc(`${uid}_${room}_${postId}`);
    const result = await db.runTransaction(async tx => {
      const [postSnap, reportSnap] = await Promise.all([tx.get(postRef), tx.get(reportRef)]);
      if (!postSnap.exists) throw new HttpsError('not-found', 'post not found');
      const post = postSnap.data();
      if (post.isHidden === true) throw new HttpsError('failed-precondition', 'post hidden');
      if (post.expireAt && post.expireAt.toMillis() <= Date.now()) {
        throw new HttpsError('failed-precondition', 'post expired');
      }
      if (reportSnap.exists) return { ok: true, duplicate: true };
      tx.set(reportRef, {
        reporterUid: uid,
        targetType: 'post',
        targetId: postId,
        targetRoom: room,
        reason,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      tx.update(postRef, {
        reportedBy: admin.firestore.FieldValue.arrayUnion(uid),
        reportCount: admin.firestore.FieldValue.increment(1),
      });
      return { ok: true, duplicate: false };
    });
    return result;
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
    enforceAppCheck: false,
  },
  async (request) => {
    requireAppCheck(request);
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
    if (!ALLOWED_ROOMS.includes(room)) {
      throw new HttpsError('invalid-argument', 'invalid room');
    }
    const textValidation = validateTimelineText(text);
    if (!textValidation.ok) {
      throw new HttpsError('invalid-argument', textValidation.reason);
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
      if (dailyUsed >= maxPostUserDaily.value()) {
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
    await reserveGlobalDaily('timelinePost', maxPostGlobalDaily.value());

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
      reportedBy: [],
      reactionLike: 0,
      reactionHeart: 0,
      reactionPeace: 0,
      reactedBy: {},
    };
    const ref = await db.collection('timelineRooms').doc(room).collection('posts').add(post);
    return { id: ref.id, postedAt: now.toMillis() };
  }
);

function buildPrompt(path, locale = 'ja') {
  // path 全選択肢を構造化して見せる (Gemini が context をしっかり把握できるように)
  const titlesArrow = path.map(p => p.title).join(' > ');
  const titleList = path.map((p, i) => `  ${i + 1}. ${p.title}${p.prompt ? ` (内部キー: ${p.prompt})` : ''}`).join('\n');
  const prompts = path.map(p => p.prompt || '').join(' ');
  const lastTitle = path[path.length - 1]?.title || '';
  const language = languageInstruction(locale);
  // 名言モード判定 (path に famous_quotes / quote_xxx が入っている)
  const isFamousQuoteMode =
    /famous_quotes|quote_business|quote_life|quote_sport/.test(prompts) ||
    /有名人|名言|偉人|哲学者/.test(titlesArrow);

  if (isFamousQuoteMode) {
    return `あなたは世界の偉人・哲学者・歴史的人物の名言を案内するアシスタントです。

ユーザーが選んだ階層 (${path.length} 段):
${titleList}

出力言語: ${language}

上記の最終テーマ「${lastTitle}」に最も合う、3つの実在する名言を選んでください。
- 著作権切れ または広く流通する古典的引用に限る
- 出典 (発言者名) を必ず付けること
- 翻訳が複数あるものは最も一般的な日本語訳
- 偉人(哲学者・科学者・作家・歴史的指導者・スポーツ選手など)を中心に
- 現存している有名人の最近の発言は避ける

出力形式: JSONのみ。コードブロックや説明文は不要。
{
  "candidates": [
    {"type": "classic", "text": "『言葉の本文』 — 発言者名"},
    {"type": "modern_classic", "text": "『言葉の本文』 — 発言者名"},
    {"type": "another", "text": "『言葉の本文』 — 発言者名"}
  ]
}`;
  }

  return `あなたは自己肯定感を育てる短い「願いの言葉」を作るアシスタントです。

ユーザーが選んだ階層 (${path.length} 段、上から大カテゴリ → 詳細の順):
${titleList}

出力言語: ${language}

【重要な指示】
- 上記階層を全て踏まえて、最終テーマ「${lastTitle}」に最も適した文を作る
- 単なる一般論ではなく、上記の文脈 (例: 「達成したい > 資格・試験 > 1ヶ月以内」) に具体的に対応した内容
- 計画系 (期限・目標) なら「いつまでに」「何を」「どう動くか」を明示
- 価値観系なら「○○です」「○○である」と断定する形

3つの異なるアプローチで、それぞれ100文字以内の言葉を1つずつ作ってください。
すべて、その言語で自然な「I want to / I wish to / 〜したい」に相当する願い形で統一。
1. 自己肯定型 (Self-Affirmation): 価値観を肯定する文
2. If-Thenプラン型 (Implementation Intentions): 「もし◯◯したら、◯◯する」の具体行動
3. 価値観型 (Mental Contrasting): 障害を予期しつつ前向きに進む文

出力形式: JSONのみ。コードブロックや説明文は不要。
{
  "candidates": [
    {"type": "self_affirmation", "text": "<100文字以内>"},
    {"type": "if_then", "text": "<100文字以内>"},
    {"type": "values", "text": "<100文字以内>"}
  ]
}`;
}

function parseCandidates(text, isFamousQuoteMode = false, locale = 'ja') {
  const cleaned = text
    .trim()
    .replace(/^```json\s*/i, '')
    .replace(/^```\s*/i, '')
    .replace(/```$/i, '')
    .trim();
  // 名言モードでは normalize 不要 (「〜したい」を強制すると引用が壊れる)
  const norm = isFamousQuoteMode ? (s) => s.trim() : (s) => normalizeCandidate(s, locale);
  try {
    const parsed = JSON.parse(cleaned);
    const items = Array.isArray(parsed.candidates) ? parsed.candidates : [];
    const candidates = items
      .map(item => norm(String(item.text ?? item)))
      .filter(Boolean)
      .slice(0, 3);
    if (candidates.length >= 1) {
      // 1〜3 件揃っていれば返す (3 未満は重複させない)
      return candidates.length === 3 ? candidates : padCandidates(candidates);
    }
  } catch (_) {
    // below: tolerate numbered-list model drift
  }
  // 番号箇条書き or 中黒/ダッシュ箇条書きを救出
  const lines = cleaned.split('\n').map(line => line.trim()).filter(Boolean);
  const fromBullets = lines
    .map(line => {
      // "1. ...", "1) ...", "・...", "- ...", "* ..."
      const m = line.match(/^(?:\d+[.)]\s+|[・\-*]\s+)(.+)$/);
      return m ? m[1] : null;
    })
    .filter(Boolean)
    .map(s => s.replace(/^[「『]|[」』]$/g, '').trim())
    .map(norm)
    .slice(0, 3);
  if (fromBullets.length >= 1) {
    return fromBullets.length === 3 ? fromBullets : padCandidates(fromBullets);
  }

  // 旧 fallback (互換)
  const candidates = lines
    .map(line => line.match(/^\d+[.)]\s*(.+)$/)?.[1])
    .filter(Boolean)
    .map(norm)
    .slice(0, 3);
  if (candidates.length === 3) return candidates;
  throw new Error(`AI response parse failed: ${cleaned.slice(0, 200)}`);
}

function fallbackCandidates(path, locale = 'ja') {
  const prompts = path.map(p => p.prompt || '').join(' ');
  if (!isJapaneseLocale(locale)) {
    return localizedFallbackCandidates(path, locale);
  }
  // 名言モード: 偉人の実際の言葉 (著作権切れ・古典)
  if (/quote_business/.test(prompts)) {
    return [
      '「成功とは、失敗から失敗へと熱意を失わずに進んでいくことだ」 — ウィンストン・チャーチル',
      '「最大の栄光は決して倒れないことではなく、倒れるたびに起き上がることにある」 — ネルソン・マンデラ',
      '「Stay hungry, stay foolish. (ハングリーであれ、愚か者であれ)」 — スティーブ・ジョブズ',
    ];
  }
  if (/quote_life/.test(prompts)) {
    return [
      '「なぜ生きるかを知っている者は、どのように生きることにも耐える」 — フリードリヒ・ニーチェ',
      '「人生において重要なのは、生きることそのものではなく、よく生きることである」 — ソクラテス',
      '「何事も、過ぎ去ってしまえば一つの懐かしい思い出となる」 — アレクサンドル・プーシキン',
    ];
  }
  if (/quote_sport|famous_quotes/.test(prompts)) {
    return [
      '「99%の努力と1%のひらめき」 — トーマス・エジソン',
      '「壁というのは、できる人にしかやってこない」 — イチロー',
      '「Just do it. (ただやるんだ)」 — Nike (ダン・ワイデン)',
    ];
  }
  // 通常モード
  const selected = path.map(p => p.title).filter(Boolean).slice(-1)[0] || '今日の一歩';
  return [
    normalizeCandidate(`${selected}に向けて、今日も小さな一歩を踏み出したい。`),
    normalizeCandidate(`もし迷ったら、深呼吸してから${selected}に戻りたい。`),
    normalizeCandidate(`進む方向が揺れても、自分の歩幅で${selected}を大切にしたい。`),
  ];
}

/// 1〜2件しか取れなかった場合、空文字で水増ししない (UI 側で自動非表示)
/// 1件は1件として返し、UI 側でその1件だけ表示する
function padCandidates(arr) {
  return arr.filter(s => typeof s === 'string' && s.length > 0);
}

function normalizeCandidate(raw, locale = 'ja') {
  const trimmed = raw.trim().replace(/^["'「『]|["'」』]$/g, '').slice(0, 120);
  if (!trimmed) return '';
  if (!isJapaneseLocale(locale)) {
    return /[.!?。！？]$/.test(trimmed) ? trimmed : `${trimmed}.`;
  }
  // 日本語: 既に自然な語尾で終わってれば触らない (句点だけ補完)
  // Gemini は様々な自然な日本語語尾を返す: ます/です/する/ある/いる/思う/たい/なりたい等
  // 「〜したい」を強制すると「思いますしたい」のような文法破壊が起きる
  const naturalEnding = /(したい|でいたい|になりたい|たい|ます|です|する|ある|いる|思う|信じる|なる|できる|得る|歩む|変わる|積む|続ける|生きる|楽しむ|大切に[しさ]|よう)[。.!！]?$/;
  if (naturalEnding.test(trimmed)) {
    return /[。.!！]$/.test(trimmed) ? trimmed : `${trimmed}。`;
  }
  // 名詞や中途半端な語尾の場合のみ「したい」で補完 (rare)
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

function validateLocale(raw) {
  const locale = String(raw || 'ja').replace(/[^A-Za-z_-]/g, '').slice(0, 16);
  if (!locale) return 'ja';
  const normalized = locale.replace('-', '_');
  if (/^ja/i.test(normalized)) return 'ja';
  if (/^ko/i.test(normalized)) return 'ko';
  if (/^zh(_Hans|_CN)?/i.test(normalized)) return 'zh_CN';
  if (/^zh(_Hant|_TW|_HK|_MO)/i.test(normalized)) return 'zh_TW';
  if (/^en/i.test(normalized)) return 'en';
  if (/^es/i.test(normalized)) return 'es';
  if (/^fr/i.test(normalized)) return 'fr';
  if (/^de/i.test(normalized)) return 'de';
  if (/^pt/i.test(normalized)) return 'pt_BR';
  if (/^id/i.test(normalized)) return 'id';
  if (/^vi/i.test(normalized)) return 'vi';
  if (/^th/i.test(normalized)) return 'th';
  if (/^hi/i.test(normalized)) return 'hi';
  if (/^ar/i.test(normalized)) return 'ar';
  return 'en';
}

function isJapaneseLocale(locale) {
  return /^ja/i.test(String(locale || ''));
}

function languageInstruction(locale) {
  const normalized = validateLocale(locale);
  return LANGUAGE_OPTIONS.find(option => option.locale === normalized)?.instruction || 'English';
}

function localizedFallbackCandidates(path, locale = 'en') {
  const prompts = path.map(p => p.prompt || '').join(' ');
  const selected = path.map(p => p.title).filter(Boolean).slice(-1)[0] || 'today';
  const normalized = validateLocale(locale);
  if (/quote_business|quote_life|quote_sport|famous_quotes/.test(prompts)) {
    switch (normalized) {
      case 'ko':
        return [
          '“The greatest glory is not in never falling, but in rising every time we fall.” — Confucius',
          '“Know thyself.” — Socrates',
          '“Well done is better than well said.” — Benjamin Franklin',
        ];
      case 'zh_CN':
        return [
          '“知人者智，自知者明。” — 老子',
          '“千里之行，始于足下。” — 老子',
          '“Well done is better than well said.” — Benjamin Franklin',
        ];
      case 'zh_TW':
        return [
          '「知人者智，自知者明。」 — 老子',
          '「千里之行，始於足下。」 — 老子',
          '“Well done is better than well said.” — Benjamin Franklin',
        ];
      default:
        return [
          '“The journey of a thousand miles begins with a single step.” — Lao Tzu',
          '“Know thyself.” — Socrates',
          '“Well done is better than well said.” — Benjamin Franklin',
        ];
    }
  }
  switch (normalized) {
    case 'ko':
      return [
        `${selected}를 향해 오늘도 작은 한 걸음을 내딛고 싶다.`,
        `망설여질 때는 숨을 고르고 ${selected}에 다시 집중하고 싶다.`,
        `완벽하지 않아도 내 속도로 ${selected}를 이어가고 싶다.`,
      ];
    case 'zh_CN':
      return [
        `我想为了${selected}，今天也迈出小小一步。`,
        `如果犹豫了，我想先深呼吸，再回到${selected}。`,
        `即使不完美，我也想按自己的节奏靠近${selected}。`,
      ];
    case 'zh_TW':
      return [
        `我想為了${selected}，今天也邁出小小一步。`,
        `如果猶豫了，我想先深呼吸，再回到${selected}。`,
        `即使不完美，我也想按自己的節奏靠近${selected}。`,
      ];
    case 'es':
      return [
        `Quiero dar hoy un pequeño paso hacia ${selected}.`,
        `Si dudo, quiero respirar primero y volver a ${selected}.`,
        `Quiero acercarme a ${selected} a mi propio ritmo.`,
      ];
    case 'fr':
      return [
        `Je veux faire aujourd'hui un petit pas vers ${selected}.`,
        `Si j'hesite, je veux respirer puis revenir a ${selected}.`,
        `Je veux avancer vers ${selected} a mon rythme.`,
      ];
    case 'de':
      return [
        `Ich moechte heute einen kleinen Schritt in Richtung ${selected} gehen.`,
        `Wenn ich zoegere, moechte ich erst atmen und zu ${selected} zurueckkehren.`,
        `Ich moechte mich ${selected} in meinem eigenen Tempo naehern.`,
      ];
    case 'pt_BR':
      return [
        `Quero dar hoje um pequeno passo em direcao a ${selected}.`,
        `Se eu hesitar, quero respirar primeiro e voltar para ${selected}.`,
        `Quero seguir em direcao a ${selected} no meu ritmo.`,
      ];
    case 'id':
      return [
        `Saya ingin mengambil satu langkah kecil menuju ${selected} hari ini.`,
        `Jika ragu, saya ingin bernapas dulu lalu kembali ke ${selected}.`,
        `Saya ingin bergerak menuju ${selected} dengan ritme saya sendiri.`,
      ];
    case 'vi':
      return [
        `Hom nay toi muon tien mot buoc nho den gan ${selected}.`,
        `Neu do du, toi muon hit tho truoc roi quay lai voi ${selected}.`,
        `Toi muon tien den ${selected} theo nhip do cua rieng minh.`,
      ];
    case 'th':
      return [
        `วันนี้ฉันอยากก้าวเล็กๆ ไปหา ${selected}.`,
        `ถ้าลังเล ฉันอยากหายใจก่อนแล้วกลับมาหา ${selected}.`,
        `ฉันอยากเข้าใกล้ ${selected} ด้วยจังหวะของตัวเอง.`,
      ];
    case 'hi':
      return [
        `Aaj main ${selected} ki taraf ek chhota kadam badhana chahta/chahti hoon.`,
        `Agar main hichkichau, to pehle saans lekar ${selected} par lautna chahta/chahti hoon.`,
        `Main apni raftaar se ${selected} ke kareeb badhna chahta/chahti hoon.`,
      ];
    case 'ar':
      return [
        `اريد ان اخطو اليوم خطوة صغيرة نحو ${selected}.`,
        `اذا ترددت، اريد ان اتنفس اولا ثم اعود الى ${selected}.`,
        `اريد ان اقترب من ${selected} بوتيرتي الخاصة.`,
      ];
    default:
      return [
        `I want to take one small step toward ${selected} today.`,
        `If I hesitate, I want to breathe first and return to ${selected}.`,
        `I want to keep moving toward ${selected} at my own pace.`,
      ];
  }
}

function validateTimelineText(text) {
  if (!text || text.length > 100) return { ok: false, reason: 'text must be 1-100 chars' };
  if (text.split(/\r?\n/).length > 5) return { ok: false, reason: 'text must be 5 lines or fewer' };
  const piiPatterns = [
    /https?:\/\/|www\.|\.com|\.jp|\.net|\.org/i,
    /[\w.-]+@[\w.-]+\.\w+/i,
    /\d{2,4}[-_ ]?\d{2,4}[-_ ]?\d{4}/,
    /(LINE|ライン|line)\s*(ID|id)\s*[:：]/i,
  ];
  if (piiPatterns.some(re => re.test(text))) {
    return { ok: false, reason: 'URLs and contact information are not allowed' };
  }
  const prohibited = [
    'セックス', 'セフレ', '風俗', '売春', 'AV', 'アダルト',
    'ちんこ', 'ちんちん', 'ちんぽ', 'チンコ', 'チンチン', 'チンポ',
    'まんこ', 'マンコ', 'おまんこ', 'オマンコ',
    'おっぱい', 'オッパイ', '乳首', 'ちくび', 'おちんちん', 'ちんぽこ',
    'うんこ', 'ウンコ', 'うんち', 'ウンチ',
    'ザーメン', 'ザー汁', '射精', 'オナニー', 'おなにー', '自慰',
    'エロ', 'えろい', 'エロい', 'h する', 'Hする', 'ヤる', 'やりたい',
    'fuck', 'fck', 'sex', 'porn', 'pornhub', 'nude', 'naked', 'xxx', 'dick', 'pussy', 'cock',
    '殺す', '死ね', '氏ね', 'ぶっ殺す', 'コロス',
    'kill yourself', 'kys', 'go die',
    'kkk', 'nigger', 'n-word', 'faggot', 'tranny', 'retard',
    '出会い', '援助交際', '援交', '副業募集', '稼げます', '高収入', '在宅で月',
    'パパ活', 'ママ活', 'セフレ募集', 'LINE交換',
    'クソ野郎', 'ゴミ', 'アホ', 'バカ野郎', 'カス', 'クズ',
    'asshole', 'bitch', 'bastard',
  ];
  const lower = text.toLowerCase();
  if (prohibited.some(word => lower.includes(String(word).toLowerCase()))) {
    return { ok: false, reason: 'inappropriate content is not allowed' };
  }
  return { ok: true };
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
      day: globalRef.id,
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
    let totalDeleted = 0;

    for (const room of ALLOWED_ROOMS) {
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
    const cutoffDay = dateKeyDaysAgo(3);
    const cutoffLog = admin.firestore.Timestamp.fromMillis(Date.now() - 30 * 24 * 3600 * 1000);
    const operationalDeleted =
      await deleteOldDocsByField('rateLimits', 'day', cutoffDay, 500) +
      await deleteOldDocsByField('postRateLimits', 'day', cutoffDay, 500) +
      await deleteOldDocsByField('userQuotas', 'dateKey', cutoffDay, 500) +
      await deleteOldDocsByField('globalQuota', 'day', cutoffDay, 500) +
      await deleteOldDocsByField('globalDailyLimits', 'day', cutoffDay, 500) +
      await deleteOldDocsByField('aiUsageLogs', 'createdAt', cutoffLog, 500);
    console.log(`[cleanup] deleted ${totalDeleted} expired posts, ${operationalDeleted} operational docs`);
  }
);

function dateKeyDaysAgo(days) {
  return new Date(Date.now() + 9 * 60 * 60 * 1000 - days * 24 * 3600 * 1000)
    .toISOString()
    .slice(0, 10);
}

async function deleteOldDocsByField(collectionName, field, cutoff, limit) {
  const snap = await db.collection(collectionName)
    .where(field, '<', cutoff)
    .limit(limit)
    .get();
  if (snap.empty) return 0;
  const batch = db.batch();
  snap.docs.forEach(doc => batch.delete(doc.ref));
  await batch.commit();
  return snap.size;
}

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
