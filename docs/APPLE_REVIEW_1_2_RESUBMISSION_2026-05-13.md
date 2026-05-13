# Apple Guideline 1.2 Resubmission Notes

対象アプリ: `マイアファメ｜毎日の自己肯定`

対象ビルド:
- Marketing Version: `1.0.6`
- Build: `27`

## 今回の追加対応

### 1. 対象年齢の明示
- タイムライン利用前の同意画面に `18歳以上` の確認チェックを追加
- 18歳以上チェックと利用規約同意の両方が揃わない限り、公開タイムラインに進めない

### 2. 利用規約 (EULA) の強化
- 不適切コンテンツ / abusive users へのゼロ寛容方針を明記
- 投稿の `報告 / ブロック / 隠す / 削除` を明記
- 24時間以内に確認し、違反投稿の削除と投稿停止措置を行うことを明記
- アプリ内のお問い合わせメールを明記

### 3. objectionable content filtering
- クライアント側: PII / URL / 連絡先 / 不適切語の即時拒否
- サーバ側: 同じ検証を Cloud Functions 側でも再実施

### 4. 報告・ブロック・即時除外
- 他人の投稿: `隠す / 報告する / このユーザーをブロック`
- 自分の投稿: `削除`
- ブロックしたユーザーは設定画面から解除可能

### 5. abusive user の停止基盤
- Cloud Functions に `bannedUsers/{uid}` チェックを追加
- BAN 済み UID は投稿 / 反応 / 通報を拒否
- 通報数がしきい値に達した投稿は自動で `isHidden=true` に変更し即時非表示

## App Store Connect 側で必ず合わせる項目

- Age Rating: `18+`
- Review Notes:
  - 公開タイムラインは 18歳以上対象
  - 初回利用時に EULA 同意必須
  - 投稿は 24時間で自動削除
  - 報告 / ブロック / 隠す / 削除を実装済み
  - 連絡先はアプリ内 `設定 > お問い合わせ` とタイムライン右上 `?` から確認可能

## Reviewer 向け短文テンプレ

This build addresses Guideline 1.2 for the public timeline feature.

- The public timeline is now explicitly limited to users aged 18+.
- Users must confirm the 18+ requirement and agree to the in-app EULA before entering the public posting flow.
- The app includes objectionable content filtering, report / block / hide / delete actions, and an in-app contact path.
- Reported content is reviewed within 24 hours, offending content is removed, and abusive users can be banned from posting.

You can verify this in:
- Timeline tab first-launch gate
- Settings > 利用規約
- Settings > お問い合わせ
- Timeline post menu (`⋯`)

## 2026-05-13 実行結果

- App Store Connect で `1.0.6 (27)` を審査対象ビルドとして再設定
- `usesNonExemptEncryption=false` を API で確認済み
- Review Notes を `1.0.6 (27)` 向けに更新済み
- `審査内容を更新` -> `App Reviewに再提出` まで実行済み
- 再提出後の状態:
  - Review Submission: `WAITING_FOR_REVIEW`
  - App Store Version: `WAITING_FOR_REVIEW`

## 再発防止メモ

- 誤ってアップロードされた `1.0.7 (27)` は今回の審査対象に使わない
- App Review の対象バージョンは常に `Marketing Version` と `Review Notes` の両方で照合する
- 未解決提出の再提出は API だけで完結しないため、UI では `審査内容を更新` -> `App Reviewに再提出` の順で進める
