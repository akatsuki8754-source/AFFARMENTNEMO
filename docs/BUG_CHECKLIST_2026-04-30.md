# コトダマ バグチェックリスト 2026-04-30

前提: 「できていない」前提で、ユーザー影響・不正利用・費用増・審査リスクを優先して確認する。

## P0: Firebase / 投稿 / Gemini / 費用

- [x] 投稿が他デバイスに見えるか
  - 確認: Firestore上は `timelineRooms/{room}/posts` を購読する設計。
  - 問題: iOS側が直接Firestoreへ `addDocument` していたため、Cloud Functions側のレート制限・予算停止を通っていなかった。
  - 修正: iOS投稿を `submitTimelinePost` callable 経由へ変更。
  - 実機相当確認: iPhone 17 Pro Maxシミュレーターから投稿し、iPhone 17 Proシミュレーターの先頭に同一投稿が表示されることを確認。
- [x] いいね/ハート/ピースが他デバイスに反映されるか
  - 問題: iOS側が直接Firestore transactionで `reactedBy` とcountを更新していた。ルールだけでは回数制限ができず、不正利用の抜け道になっていた。
  - 修正: `reactToPost` callable 経由へ変更。1分/1日上限、投稿の非表示/期限切れチェックを追加。
- [x] 通報が費用・荒らしの抜け道にならないか
  - 問題: clientが `reports` collectionへ直接作成でき、同一ユーザーの重複通報も増やせた。
  - 修正: `reportPost` callable 経由へ変更。重複通報は同じdoc idで1回だけ集計。
- [x] Firestore直書きの抜け道
  - 修正: rulesで `timelineRooms/*/posts` のclient createを禁止。updateは自分の投稿を `isHidden=true` にする用途だけ許可。
  - 修正: `reports` はclient create/update/delete禁止。
- [x] 投稿内容のサーバ側検証
  - 問題: client側にはPII/NGワード検証があるが、Functions側は長さとroomだけだった。
  - 修正: URL/メール/電話/LINE ID/NGワードのサーバ側検証を追加。
- [x] Geminiの利用制限
  - 確認: ユーザー日次上限、グローバル日次上限、予算停止フラグあり。
  - 追加: ユーザー分間上限、グローバル分間上限を追加。
- [x] Geminiが表示されない原因
  - 原因候補: `system/aiRuntime.clientEnabled` がfalse/未作成、Functions未deploy、Secret未設定、Blaze未完了、`AI_GENERATION_ENABLED=false`。
  - 修正: deploy後に有効化する `firebase/deploy_after_blaze.sh` を更新。iOSはlocale付きで `aiGenerateWish` を呼ぶ。
- [x] App Check
  - 問題: iOSはAppCheck providerを設定していたが、App Attest entitlementsがなかった。Functions側も `enforceAppCheck=false` だった。
  - 修正: App Attest production entitlementを追加し、user-facing callable functionsでApp Check必須チェックを追加。
  - 確認: App Attest設定、debug token登録、App Checkなしの直叩き拒否、debug token登録後のシミュレーター投稿成功を確認。
- [x] 費用増・古いデータ残り
  - 修正: 期限切れposts削除に加え、rate limit / quota / usage logの古い運用doc削除を追加。
  - 修正: 言語ルーム追加後も削除漏れが出ないよう、期限切れposts削除の対象roomを共通許可リストから生成。
  - 残確認: Firestore TTL policyを本番Console側でも `expireAt` に設定できるなら追加。
  - 残課題: Cloud Functions Node.js 20 runtimeが2026-10-30に廃止予定。Node.js 22への移行が必要。

## P1: AIウィザード

- [x] 1問目に「有名人の言葉」
  - 確認済み: root直下に存在。
- [x] 選択肢が名詞止まりで願い感が弱い
  - 修正: 主要カテゴリを「〜したい」型へ寄せた。
- [x] 条件不足
  - 修正: 燃え尽き、自己責め、過去、喪失、境界線、休息、自己受容、見た目/体型、発信、居場所、挑戦を追加。
- [x] Gemini出力のlocale
  - 修正: iOSからアプリ内言語設定を優先したlocaleを送信し、Functions prompt側で出力言語を指定。
- [x] 日本語以外で候補末尾に「したい」が付く
  - 修正: iOS/Functions双方のnormalizeで日本語以外は日本語語尾を付けない。
- [ ] 名言候補の権利・正確性
  - 残課題: 現在のfallbackには近現代引用が混ざる。審査・権利面では古典/著作権切れ中心に再整理した方が安全。

## P1: ローカライズ

- [x] 設定/タイムライン言語ルームが英日中心に見える
  - 修正: 言語選択を共通カタログ化し、日本語/英語/簡体字/繁体字/韓国語/スペイン語/フランス語/ドイツ語/ポルトガル語/インドネシア語/ベトナム語/タイ語/ヒンディー語/アラビア語を同じ選択肢として表示。
  - 修正: Functionsの投稿room許可とGemini出力言語も同じ言語セットへ拡張。
- [x] 設定に中国語/韓国語があるのにString Catalogが英日だけ
  - 修正: `zh-Hans` / `zh-Hant` / `ko` を `CFBundleLocalizations` とString Catalog全キーへ追加。
- [ ] 翻訳品質
  - 残課題: 追加localeは全キーが欠落しない状態にした段階。自然な翻訳としては人手/翻訳APIでレビューが必要。
- [ ] ハードコード文言
  - 残課題: SwiftUI内に日本語直書きが残っている。次工程で `LocalizedStringKey` / String Catalogへ移す。

## P1: タイムラインUX

- [x] 自動更新されない可能性
  - 問題: anonymous sign-in完了前にlistenerを貼るとpermission deniedで止まる可能性。
  - 修正: listener開始前に匿名サインイン完了を待つ。
- [x] プル更新
  - 確認: `.refreshable` あり。fetch前に匿名サインインするよう修正。
- [x] 反応数が0に見える可能性
  - 問題: Firestore numericが `NSNumber/Int64` で返る場合に `as? Int` が落ちる可能性。
  - 修正: numeric decode helperを追加。

## P2: 既存機能の確認観点

- [ ] ホーム: 起動時自動再生ON、AI再生default、通知タップ導線
- [ ] 読み上げ: AI音声/録音/自分で読むの選択、音声変更後に即終了しないか
- [ ] 録音: 再生・削除・カードtapで録音開始しないか
- [ ] 言葉追加/編集: 通知設定重複削除、下部登録ボタン、入力欄高さ、カテゴリカスタム入力
- [ ] 言葉一覧: フィルタ後全選択、一括削除、長押し複数選択
- [ ] 読み上げセット: 対象曜日外除外、録音欠落時の自動fallback、長押し編集
- [ ] オンボーディング: 投稿数増加演出、再表示ボタン
- [ ] 設定: 閉じるボタン不要化、バックグラウンドAI音声トグルの権限/制約説明
- [ ] App Store / Google Play metadata: `app-ads.txt`、privacy、review notes、Android移植時のFirebase App Check Play Integrity

## 検証コマンド

- `node --check firebase/functions/index.js`
- `plutil -lint AFFARMENTNEMO/Info.plist AFFARMENTNEMO/AFFARMENTNEMO.entitlements`
- `python3 -m json.tool AFFARMENTNEMO/Resources/Localizable.xcstrings`
- `firebase deploy --only firestore:rules,firestore:indexes --project kotodama-86a14`
- `firebase deploy --only functions --project kotodama-86a14`
- `xcodebuild -project AFFARMENTNEMO.xcodeproj -scheme AFFARMENTNEMO -destination 'generic/platform=iOS Simulator' build`
