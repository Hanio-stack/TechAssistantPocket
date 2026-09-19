# TechAssistantPocket Work Log

このファイルには、実際に行った作業・設計判断・検証結果を時系列で残す。

実装予定そのものは GitHub Issues、長期的な仕様は `docs/DESIGN.md`、ここには「何をしたか / 何が分かったか」を記録する。

---

## 2026-09-19

### UI 参照画像を修復

- `docs/ui/today.png`
- `docs/ui/insights.png`
- `docs/ui/task-insight-detail.png`

上記 3 ファイルは PNG データが破損していたため削除した。

代わりに Git 上でも差分確認しやすく、GitHub 上でそのまま描画できる SVG として再作成。

- `docs/ui/today.svg`
- `docs/ui/insights.svg`
- `docs/ui/task-insight-detail.svg`

UI の方向性は維持し、Today / Insights / Task Insight Detail の実装参照として使用する。

### 実装前ドキュメント整合性

- Claude レビューで挙がった Blocker は DESIGN.md 側で解消済み
- Review 再発火、Task 実行時刻、既存 Task への予定追加、Archive、通知責務も仕様化済み
- UI 参照アセット修復後、Architecture Review Issue #1 を完了扱いにする

### 実装前の Task / 通知仕様を確定

- `actualExecutedAt` は「実際に Task を開始した時刻」と定義
  - 完了時刻ではない
  - MVP では実際の終了時刻は保存しない
- 日時あり Task の所要時間は初期値 30 分
  - ユーザーは変更可能
  - 未スケジュール Task は所要時間未設定でもよい
- Tasks 画面から既存 Task を選び、`予定を追加` できるようにする
  - 同じ行為を毎回新しい Task として作らず、既存 Task.id に TaskOccurrence を追加する
  - Task 単位の履歴・Insights を継続できるようにする
- 未スケジュール Task を予定なしで実行した場合の記録方法を確定
  - 新しい TaskOccurrence を作成
  - `scheduledStart / scheduledEnd / planResult = nil`
  - `actualExecutedAt = 実際の開始時刻`
- Task のユーザー向け「削除」は MVP では Archive とする
  - 過去の TaskOccurrence は保持
  - 未来の pending TaskOccurrence のみ削除
  - 対応するローカル通知と Calendar ミラーも削除
- 通知の二重発火を防ぐ責務分離を確定
  - Pocket Task = UserNotifications のみ
  - Task の EventKit ミラーには Calendar Alarm を付けない
  - 通常 Event = EventKit の Calendar Alarm

---

## 2026-09-15

### MVP 設計の再整理

- Task と通常 Event を明確に分離
  - Task = 達成対象、分析対象、正本は SwiftData
  - Event = 映画・食事・会議など、評価対象外、正本は EventKit
- `+` から Task / 予定へ分岐する最小導線に統一
- Task の優先度を MVP から削除
  - 現時点で並び替え・通知・提案のいずれにも利用しないため
- Review の独立タブを削除
  - その日の Task がすべて確定した、または最後の予定終了時刻を過ぎた時に Today 内へ Review 導線を出す
  - 固定のレビュー時刻 / 就寝時刻設定を持たず、当日の Task に追従する
- 選択済み Calendar が iPhone から消えた場合は、Task を保持したまま再選択を要求する
- Calendar の正本ルールを確定
  - Pocket Task = SwiftData が正本、Calendar はミラー
  - 通常 Event = EventKit が正本
- 完全な Calendar 双方向同期は MVP 対象外のまま維持

### 予定と実行の記録方法

- `Task + TaskOccurrence` の 2 モデル中心を維持し、ScheduledOccurrence / ExecutionRecord への分割は行わない
- TaskOccurrence に次を持たせる方針
  - `scheduledStart / scheduledEnd`
  - `planResult`
  - `actualExecutedAt`
  - Calendar 対応 ID
- 例: 英語学習を 10:00 に予定したが 18:00 に実行した場合
  - 10:00 = `missed`
  - 18:00 = `actualExecutedAt`
  - 「予定は失敗したが後で実行できた」という両方の事実を保存する
- 開始前の予定変更は失敗扱いしない
- 開始後の再スケジュールは旧 TaskOccurrence を `missed` とし、新しい TaskOccurrence を作る

### Insights の整理

- 1ページ目は以下だけに限定
  - 今週の予定成功率
  - Task 別一覧
- Task 詳細で曜日 / 時間帯の傾向を見る
- 「予定成功率」と「実際に行動できた時間」の観測を区別する
- 後から実行した場合、予定時刻には失敗、実行時刻には成功観測を残す

### 実装境界

MVP を肥大化させない範囲で以下の薄い境界を採用する。

- `TaskRepository` -> SwiftData
- `CalendarService` -> EventKitAdapter
- `NotificationService` -> UserNotifications
- `InsightsEngine` -> 純粋ロジック
- `SuggestionEngine` -> 純粋ロジック

大規模 Clean Architecture にはしない。

### Claude レビュー反映

- `planResult` の意味を `pending / success / missed / cancelled` として明文化
- `success` は `actualExecutedAt` が `scheduledStart ... scheduledEnd` の範囲内にある場合と定義
- `scheduledEnd` 経過だけでは自動で `missed` にせず、完了操作 / 再スケジュール / Review で確定する方針を明文化
- Task の所属日は `scheduledStart` のローカル日付と定義
- 予定 Task が 0 件の日は Review を出さない
- 日付またぎの Task は開始日側の Review 対象とし、翌日は `昨日を振り返る` として扱う
- **Review 完了後に同日へ新しい予定 Task が追加された場合、その日の Review 完了状態を無効化し、再度 Review を出せるようにする方針へ修正**
  - 後から追加された Task が `pending` のまま残り、成功率の分母から漏れることを防ぐため
- 上記ケースを `docs/DESIGN.md` と MVP テストケースに追加

### ドキュメント更新

- `README.md` を現行 MVP 方針へ更新
- `docs/DESIGN.md` を現行の確定仕様へ更新
- `CLAUDE.md` を追加
- `docs/CLAUDE_REVIEW_REQUEST.md` を追加し、実装前に Claude Code へ設計レビューさせる準備を実施

---

## 2026-09-09

### プロジェクト再開

- TechAssistantPocket の最小設計を再整理
- コア価値を「予定管理」ではなく「実行履歴から予定の立て方を改善すること」と再定義
- MVP の技術構成を以下に整理
  - SwiftUI
  - SwiftData
  - EventKit
  - UserNotifications
- OpenAI API、自前サーバー、Google Calendar API の直接利用は MVP では行わない方針
- Local First / 運用コスト 0 を優先する方針を確認

### Google Calendar 連携の実機確認

- iPhone 標準カレンダーに Google アカウント由来のカレンダーを表示できることを確認
- iPhone 標準カレンダーで、Google アカウント配下のカレンダーを保存先として指定すると Google Calendar 側へ同期されることを実機で確認
- よって MVP では Google Calendar API を直接利用せず、EventKit 経由の連携で進める
- 注意点として、Google Calendar を使うユーザーは iPhone 側に Google カレンダーアカウントを追加している必要がある

### ドキュメント整備

- `README.md` にコンセプト / 設計思想 / MVP / 技術構成を追記
- `docs/DESIGN.md` に初回起動から日常利用までのユーザーフロー、データ責務、成功率ロジック、画面構成を追加
- 今後は GitHub を仕様と作業履歴の正として利用する

### dev-knowledge 連携方針

- 共有ノウハウリポジトリ `Hanio-stack/dev-knowledge` を TechAssistantPocket 開発時の参照元として使う方針を追加
- 実装前に、今回の作業に関係する Rules / Patterns / Failures / Knowledge だけを確認する
- プロジェクト固有の仕様・既存実装を共有ノウハウより優先する
- 大きな依存追加や戻しにくいアーキテクチャ変更は Human Gate を置く
- 作業区切りで Knowledge Review を行い、十分に検証され他プロジェクトでも再利用価値がある知見だけ `dev-knowledge` への追加候補とする
- ライブラリ化は早すぎる抽象化を避け、TechAssistantPocket 内で API と責務が安定してから判断する
- 詳細を `docs/DEVELOPMENT_KNOWLEDGE.md` に記録

---

## 記録テンプレート

```md
## YYYY-MM-DD

### 作業
- 

### 決定
- 

### 検証結果
- 

### 次にやること
- 
```
