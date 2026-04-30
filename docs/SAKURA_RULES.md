# Sakura (擬似投稿) 仕様

`SakuraTemplateProvider.swift` の挙動を明文化したもの。

## 目的
- タイムライン (みんなの願い) が空でも閑散としないよう、ローカルで擬似投稿を表示
- リアル投稿が増えると自動的に表示比率が下がる (リアル優先)
- 24h で「天に流れて消える」演出を維持

## 表示数ルール
```swift
target = max(0, 100 - realPostCount)
```
- リアル投稿 0件 → 擬似 100件
- リアル投稿 30件 → 擬似 70件
- リアル投稿 100件以上 → 擬似 0件 (完全消滅)

## 並び替えルール
- **シード**: `dailySeed = year * 10000 + month * 100 + day` (例: 2026/04/30 → 20260430)
- **アルゴリズム**: `SeededGenerator` (SplitMix64) で決定論的シャッフル
- **更新タイミング**: 毎日 0時 (ローカル時刻) で並びが変化
- **同じ日の中**: アプリを開き直しても同じ並び (体感ブレ防止)

## 24h消滅演出
各擬似投稿に以下を仕込む:
- `createdAt = now - (1〜23h前のランダム)`
- `expireAt = createdAt + 24h`
- フィードはクライアント側で `expireAt > now` フィルタ済み (TimelineView)

→ 表示時点で「天に流れていく途中」の状態が再現される。

## コスト
- **Firestore 書き込み: なし** (運用費 0円)
- セキュリティルール変更不要
- 全てクライアントローカル処理

## 多言語
- ロケール切替で別プールに即切替
- 言語別テンプレ:
  - 日本語: 200+
  - 英語: 50+
  - 中国語(簡): 50+
  - 中国語(繁): 50+
  - 韓国語: 50+

## ID命名規則
擬似投稿は `id` プレフィックスで区別:
```
sample_<roomCode>_<index>
```
例: `sample_ja_JP_42`

`SakuraTemplateProvider.isSample(post)` で判定可能。

## Phase 3 拡張 (将来)
`firebase/functions/index.js` の `sakuraSeeder` (15分ごとに onSchedule) で
Firestore に投稿してリアル感を増す案あり。**現状は無効化** (運用費抑制のため)。
