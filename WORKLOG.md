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

## 2026-09-20

### Phase 1: Task domain foundation

- `Item` を `Task` / `TaskOccurrence` の SwiftData モデルと `PlanResult` に置換し、App のスキーマを更新。サンプルの追加・削除画面はアプリ名だけの仮表示にした。
- DESIGN.md の全フィールドを保持。UUID の `taskID` で関連づけ、Relationship は導入しない。`category: String?` は保存のみ、所要時間は秒単位の `TimeInterval?` とした（ユーザー承認済み）。
- 予定ありの生成で duration 未指定時だけ30分を適用。自発実行は予定開始・終了・結果が nil で、実際の開始時刻を保存する。
- pending の予定に対する実行記録・未実行確定・キャンセルのみ実装。予定枠の両端を含む実際の開始なら success、枠外なら missed。時間経過で自動確定しない。確定済み結果や自発実行の訂正、再スケジュール API は対象外。
- MainActor の薄い `TaskRepository` を追加。追加・取得・明示的保存・Archive を提供し、存在しない Task ID の Occurrence 挿入を拒否。取得したモデルの編集後は save() を呼ぶ。専用 ModelContext の利用を想定し、保存対象は同 Context 全体。
- Archive は過去と確定済みの履歴を保持し、現在より後の pending のみ削除。将来のサービス連携用に削除対象の Occurrence ID と Calendar 対応 ID を返す。Calendar・通知の実処理はない。
- EventKit、通知、Review、Insights、Suggestions、最終 UI、外部依存、Item データ移行は追加していない。

### 準備・判断・Knowledge Review

- AGENTS.md、README.md、DESIGN.md、DEVELOPMENT_KNOWLEDGE.md、CLAUDE.md、既存 WORKLOG、コード・テスト・Xcode 設定・Git 状態を確認。関連 Issue は取得できず、今回の依頼と現行仕様を基準にした。
- 共有 `dev-knowledge` の `rules/ai-development.md` と `rules/development-principles.md` を参照し、小さい変更・仕様優先・検証後の判断を適用。カテゴリ UI、ライブ外部サービス検証、共有ライブラリ化は対象外。
- 初回は iPhone 16e Simulator の並列クローン起動で Accessibility / launchd のタイムアウトが発生。起動済み iPhone 17 Pro と `-parallel-testing-enabled NO` で起動テストが通ることを確認。
- 初案の rollback API は、保存後に直接編集したモデルの値復元テストに失敗。processPendingChanges() を加えても再現したため、Phase 1 必須範囲外の取り消し API を撤去。保存・取得境界に限定した。SwiftData 全般の障害とは一般化しない。
- Knowledge Review: 今回はプロジェクト固有の仕様と単一環境での観測。共有知識への追加・ライブラリ抽出は行わない。

### Phase 1 再開時の最終検証

- 未コミット差分と現行仕様を再確認。今回は実装コードを変更せず、前回未記録だった最終検証を完了した。
- `xcodebuild -list -project TechAssistantPocket/TechAssistantPocket.xcodeproj` で scheme `TechAssistantPocket` を確認し、`simctl list devices available` で実在する検証先を確認。
- `xcodebuild build test -project TechAssistantPocket/TechAssistantPocket.xcodeproj -scheme TechAssistantPocket -destination 'platform=iOS Simulator,id=D08C826D-EC7A-4D79-A683-B4C5771875CF' -derivedDataPath /tmp/pocket-phase1 -parallel-testing-enabled NO -only-testing:TechAssistantPocketTests -only-testing:TechAssistantPocketUITests/TechAssistantPocketUITests/testExample` は終了コード 0、BUILD / TEST SUCCEEDED。単体テスト5件（時刻境界のパラメータ5ケースを含む）と起動テスト1件が成功。
- Simulator の初回起動・テスト用アプリのインストール待ちが長かったため、起動済み iPhone 16e（`BFF2E34B-7644-4FE2-B503-F0D5B1CD8782`）でも `test-without-building` と `-only-testing:TechAssistantPocketTests` で切り分け、単体テスト5件成功。iPhone 17 Pro 側も最終的に成功し、コード修正は不要だった。
- ログ: `/tmp/pocket-phase1-retest.log`、`/tmp/pocket-phase1-unit-retest.log`。結果バンドルは `/tmp/pocket-phase1/Logs/Test/`（一時ファイル）。`git diff --check` も成功。
- 検証範囲はドメイン・Repository とアプリ起動。既存起動テストには画面内容の assertion がなく、最終 UI や狭幅日本語レイアウト、実機、Calendar・通知連携は今回未検証。永続化テストはメモリ内ストアを別 ModelContext で読み直すもので、ディスク再起動・移行の検証ではない。
- Knowledge Review: 起動待ちはこの環境での観測として記録し、一般ルールには昇格しない。コミット・push は行っていない。

## 2026-09-20 — Remaining MVP

### 準備と範囲

- `feature/mvp-complete` で Phase 1 から継続。AGENTS / README / DESIGN / DEVELOPMENT_KNOWLEDGE / CLAUDE / WORKLOG、UI README と全3 SVG（ソース・画像）、Xcode project と既存コード・テストを確認。GitHub の Issue 一覧取得結果は空だったため、今回の明示的依頼と現行仕様を基準にした。
- `Hanio-stack/dev-knowledge` の `rules/ai-development.md`、`rules/development-principles.md`、`patterns/mobile-japanese-layout-wrapping.md` を参照。仕様優先・小さい可逆変更・日本語の縦積みを適用。Web/CSS 固有の指示、外部 CI 構築、共有ライブラリ化は適用しない。
- Xcode 26.3 (17C529)、既存 scheme `TechAssistantPocket`、iOS 26.3.1 Simulator を確認。EventKit の full-access API / usage description は Apple の TN3152 と SDK を確認。読み取りとミラー更新のためイベントの full access を使い、Reminders / Contacts の権限は追加しない。

### 実装

- Today / Tasks / Insights の3タブ、各タブの共通 +（Task / 通常 Event）、設定、初回案内を追加。iPhone 専用に project の device family を合わせ、日本語を development region に設定。
- Tasks: 作成・編集・予定追加（未指定30分）・予定なし実行の開始時刻記録・Archive。カテゴリは任意の文字列保存のみ。優先度は追加していない。
- Today: Task と通常 Event の時間順表示。通常 Event に完了操作を付けず、全履歴の mirror ID で二重表示を除外。Task はローカル開始日に所属し、日付またぎミラーも除外する。過去日の表示、再読み込み、日付変更時の更新を追加。
- `CalendarService` / `EventKitAdapter`: 権限要求、書き込み可能カレンダー一覧、選択先の直前検証、通常 Event 読み込み・作成、Task ミラーの作成・更新・削除。Task を先に SwiftData へ保存し、連携失敗は再試行可能な表示にする。選択先消失時は自動的に別カレンダーへ書かず、再選択を要求。外部削除されたミラーの ID は解除する。
- Archive で削除できなかったミラー識別子は UserDefaults に保持し、再起動後も再試行可能にした。削除待ちミラーも Today から除外する。全同期・Google API・バックエンドは追加していない。
- `NotificationService`: Task 通知は occurrence ID ごとの UserNotifications のみ。通知設定を予定ごとに保持するため `notificationMinutesBefore: Int?` を追加（nil は通知なし）。既定値と許可は設定画面で扱う。Archive・結果確定・再スケジュールで不要な通知を除去する。通常 Event の通知は EventKit Alarm のみ。Task ミラーは既存 Alarm もクリアする。
- 再スケジュール: 開始前は同一 occurrence を更新。開始時刻以降は旧予定を missed とし、新規 pending occurrence を作成。missed かつ未実行の枠も履歴を保持したまま再予定可能。success / cancelled / 実行済み履歴の一般的な訂正機能は追加していない。
- Review: `ReviewRecord` と純粋な `ReviewPolicy` を追加。予定ゼロの日は非表示、全結果確定または最終終了を過ぎた日に CTA を表示し、直近の未レビュー日を扱う。新規予定・移動先への予定追加で Review を無効化。予定どおりは予定開始時刻を実際の開始として記録する旨を表示し、後で実行した場合は実際の開始を入力する。Review タブは追加しない。
- `InsightsEngine`: Foundation の値型だけで集計。予定成功率は scheduled success / (success + missed)、pending / cancelled / 予定なしは除外。予定枠と実際の開始時刻の観測を別に扱い、同じ成功を同一曜日・時間帯で二重計上しない。時間帯は 0–6 / 6–12 / 12–18 / 18–24 時。
- `SuggestionEngine`: 同一 Task の現在条件に3件以上・成功率40%以下、別条件に成功観測3件以上・観測成功率2/3以上・改善幅25ポイント以上を必要とする説明可能なルール。過去の成功時刻から次の14日内の候補を出し、通常 Event と他の pending Task の空き時間を確認。変更は確認アラートで承認後のみ行い、直前に重複と候補時刻を再検証する。
- SwiftData の既存2モデルを維持し、仕様どおりの ReviewRecord と任意の通知フィールドだけを追加。破壊的移行・外部依存は追加していない。データを開けない場合は削除せずエラー画面を表示する。

### 検証中に発見・修正した問題

- MainActor service のデフォルト引数初期化と SwiftUI Section の initializer のコンパイルエラーを修正。
- Review の初回 sheet が空になる実 UI 不具合を検出。日付と表示フラグを別々に管理せず、日付を持つ item で sheet を表示するよう修正。
- アクセシビリティ文字サイズで成功率リングと件数が重なったため、大きい文字サイズでは数値を縦積みに変更。
- 提案の確認を明示的な変更 / キャンセルを持つ標準 alert に変更し、キャンセル操作を UI テストで確認。
- 実 EKEvent のペイロードテストで、外部から終日化されたミラーの時刻が丸められることを検出。`isAllDay = false` を日時代入より先に行うよう修正し、回帰テスト成功。
- 通知の日時成分に calendar / timeZone を保持し、Task の絶対日時から通知を組み立てる。実 UNNotificationRequest / UNCalendarNotificationTrigger の内容を検証。
- カレンダー再試行の対象に確定済み予定も含め、連携失敗後に結果を記録した場合もミラーを作成可能にした。カレンダー取得失敗時は古い Event 表示をクリアする。
- レビュー済みの missed を再予定する場合、内容が変わらない元の日の Review は保持し、新しい予定日の Review を無効化する。回帰テストを追加。
- 提案承認後に別の pending 予定への提案が表示されても正常なので、UI テストはボタン全体の消失ではなく、承認した候補の消失／変更を確認する。

### 検証結果

- 各区切りの `xcodebuild build test` → 診断 → 修正 → 再実行を実施。単体テストは23件（パラメータケースを別途含む）が成功。境界、分母、実行傾向、Review 条件・無効化、Archive、再予定、ミラー除外、提案の最低観測数と重複、連携失敗・再試行、ディスク再オープンを含む。
- iPhone 16e（390pt）で UI 操作テスト4件、通常起動4構成が成功。Task の作成・編集・予定追加・自発実行・結果記録・Archive、Review、Insights、提案のキャンセルと承認、通常 Event 作成、カレンダー拒否時の Task 作成と Event 権限案内を操作。日本語の通常文字・アクセシビリティ文字のスクリーンショットを目視確認。
- UI 操作テストは `--ui-testing` の明示指定でメモリ内データとテスト専用 Calendar / Notification service を使う。個人カレンダーや本物の通知を変更しない。これらを実 EventKit 保存・通知配信の検証とは扱わない。テスト用サービス・シードは DEBUG のみ。
- 通常アプリの起動 smoke はテスト用引数なしで SwiftData と本来のサービスを初期化する。権限要求ボタンは自動的に押さない。
- 一時ログ・結果: `/tmp/pocket-mvp-*.log` と `/tmp/pocket-mvp/Logs/Test/`。成功した390pt UIの画像は `/tmp/pocket-mvp-ui-passing/`。
- 375pt の iPhone SE（3rd generation）を `Pocket MVP Narrow`（`F5AAAF6B-4297-43B8-B161-F42B0E6E9D2E`）として作成。初期の2回は XCTest の接続前にランナーが終了したが、他の Simulator を終了し、対象を再起動してアプリの起動完了後に再実行すると接続できた。
- 狭幅 Review の失敗録画を確認し、画面自体は開いているが完了ボタンが画面外にあることを確認。テストを画面確認、未確定の分類、完了ボタンへのスクロールの順に修正。Insights の Task 行・提案・新規 Event も、画面内へスクロールしてから操作・検証する。アプリの機能や設計は変更しない。
- 起動 smoke の横向きが次の操作テストへ残るため、操作テストは開始時に縦向きを明示する。向きが残った状態でも Review から Event 作成までの該当テストは成功したが、画像が正しく評価できないため、縦向きで全テストを再検証した。修正前の進行中テスト1回は意図的に中断した。
- 最終コマンド: `xcodebuild clean build test -project TechAssistantPocket/TechAssistantPocket.xcodeproj -scheme TechAssistantPocket -destination 'platform=iOS Simulator,id=F5AAAF6B-4297-43B8-B161-F42B0E6E9D2E' -derivedDataPath /tmp/pocket-mvp -parallel-testing-enabled NO`。終了コード0、CLEAN / BUILD / TEST SUCCEEDED。単体23件（6 suite、パラメータケースを別途含む）、UI操作4件・通常起動4構成の計8件がすべて成功。
- 最終結果: `/tmp/pocket-mvp/Logs/Test/Run-TechAssistantPocket-2026.09.20_22-21-47-+0900.xcresult`、ログ `/tmp/pocket-mvp-finalnarrow.log`。画像 `/tmp/pocket-mvp-narrow-final/` で375ptの Review、提案、通常 Event 入力、日本語の折り返しを確認。通常文字・アクセシビリティ文字の確認に加え、390ptの明色と375ptの暗色の画面を目視確認した。
- 最終差分を仕様と照合。残存するアプリのコンパイル・テスト失敗はなく、外部依存や機能範囲の追加はない。再開後の失敗修正は UI テストのスクロール・画面方向・提案適用後の判定に限定した。
- 全テスト後、375pt Simulator を起動してテスト引数なしの通常アプリを開き、初回案内が表示されることを確認。画像は `/tmp/pocket-mvp-normal-launch.png`。実際のカレンダー権限やアカウント操作は行っていない。最終 `git diff --check` は成功。

### Knowledge Review と実機フォロー

- 今回の EventKit 日時設定順序と SwiftUI sheet の修正は回帰テストを追加して検証。現時点ではこのアプリ内の知見として記録し、共有ノウハウへの追加やライブラリ抽出は行わない。
- 実 iPhone での権限許可・拒否と復帰、iOS に設定済み Google カレンダーの表示・同期、通知の実配信、カレンダー削除・再選択、最終的な日本語 UI の使い心地は未検証。実機・アカウント操作が必要なフォローとして分離する。
- README / DESIGN は変更していない。コミット・push は行っていない。
