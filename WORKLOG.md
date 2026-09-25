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

## 2026-09-21 — Today の祝日除外と今 / 次の表示

### 調査・原因

- README → DESIGN → DEVELOPMENT_KNOWLEDGE、AGENTS / CLAUDE / WORKLOG、Today の UI SVG、現行コード・テスト・Git 差分を確認。関連 Issue は設計レビュー #1 のみで、今回の実機報告を修正仕様として扱った。
- `dev-knowledge` の AI 開発原則と日本語の狭幅レイアウトを参照。既存の薄い境界を維持し、長文は折り返す。Web 固有の CSS 指示や新しい共通ライブラリは適用しない。
- EventKitAdapter は `calendars: nil` で全カレンダーを取得していた。読み取り専用の祝日・購読カレンダーも通常 Event として返し、Today はミラー ID 以外を除外していなかった。取得ごとにメモリ上の events を置き換えており、通常 Event を SwiftData に保存・Task 化する経路はない。
- 同一祝日が別カレンダーにあれば、異なる identifier の Event として両方が表示される。実機の具体的な calendar/source ID は未取得なので、今回の重複がどのアカウントの組み合わせだったかは断定しない。SDK の `calendarItemExternalIdentifier` の説明でも、複数アカウントの購読・ICS 複製等で重複し、繰り返しの各回も同じ外部 ID になり得ることを確認。
- SDK の公開情報は calendarIdentifier / calendar.title / type / isSubscribed / allowsContentModifications、および source の identifier / title / type。Event は eventIdentifier、calendarItemExternalIdentifier、title、URL 等を取得できるが、公開の holiday フラグ・購読フィード URL はない。外部 Event ID や Event の URL を祝日カレンダーの ID と同一視しない。private API は使わない。
- Today は開始日が合う全 Task と重なる Event を時刻順に表示するだけで、結果・終了時刻による表示分離と初期フォーカスがなかった。既存の Task の終了境界は success 判定で両端を含むため維持する。
- 作業開始時から存在した Xcode project の DEVELOPMENT_TEAM 設定はユーザー変更として保持し、編集していない。

### 修正

- `CalendarReadPolicy` を Foundation の値型・純粋判定として追加。編集可能なカレンダーは除外しない。読み取り専用で、購読または CalDAV / Exchange のカレンダーについて、日本語・英語の既知の祝日カレンダー名を判定する。Google 祝日フィード識別子が calendarIdentifier に現れる場合も判定する。Event 名や終日属性だけで除外しない。
- Adapter は判定したカレンダーを読み取り predicate から外す。対象が0件なら即座に空配列を返し、誤って全カレンダーに戻さない。同じ方針を Today と提案の空き時間判定に適用する。重複除去は calendar ID + event ID + start の完全一致だけで、別カレンダーの通常予定や別の繰り返し回は保持。
- `Timeline.presentation` は日付所属・ミラー除外を保ちつつ、現在/未来、時間を過ぎた未確定、結果確定/終了済みに分ける。未確定と履歴は別の折りたたみで初期状態は閉じる。Task の result、実行時刻、通知、DB レコードは変更しない。
- 今は pending Task の start <= now <= end、Event の start <= now < end。時刻付きの現在項目を優先し、なければ次の時刻付き項目をフォーカス。個人の終日予定は時系列に残すが、時刻付きの行動があればそちらへフォーカスする。
- ScrollViewReader と既存 List を使い、初回・ローカル表示日/タイムゾーン変更・表示日の Task の結果確定時だけ中央への位置調整を要求する。通常の再取得、タイマー更新、同日へのタブ復帰は強制スクロールしない。時刻表示は30秒間隔・foreground・significant time change・手動再取得で更新。未スケジュールと日付またぎの開始日所属は維持。
- 既存 DB の cleanup は不要。通常 Event は永続化していないため、新しい取得結果でメモリ表示が置き換わる。Task / Occurrence / ReviewRecord の schema、TaskRepository、InsightsEngine、通知・カレンダー書き込みは変更していない。
- 今回ユーザーが指定した Today の変更を DESIGN 7.1 / 13.6 に追記。テスト専用の16時固定時計・完了4件/未確定/現在/次/個人終日/重複祝日の fixture を DEBUG 引数時だけ追加した。

### 検証・Knowledge Review

- 初回ビルドの Timer.autoconnect の Combine import 不足を修正。単体33件（パラメータケース別途）、375pt の新規 UI テスト2件が成功。時刻境界・分母維持・日付所属・タイムゾーン・23/25時間の夏時間日・購読/Google由来の祝日・個人終日・別カレンダー/繰り返しの保持を検証。
- 新規 UI テストでは中央付近のフレーム位置、結果記録直後の次 Task への移動、折りたたみ履歴の取り出し、タブ復帰時の閲覧位置保持、Tasks / Insights に残る完了履歴、大きい文字で次 Task が見えることを確認。画像 `/tmp/pocket-today-focus-images/` を目視確認。
- UI の Calendar は fixture であり、実 iPhone の購読メタデータや Google 同期を検証したものではない。改名・未対応言語・識別子が opaque なカレンダーの祝日判定には制約がある。未知の読み取り専用カレンダーを一律に隠さない。
- Knowledge Review: EventKit のメタデータ制約は SDK と公開文書で確認したが、プロバイダーごとの実機検証は未実施。今回の判定を汎用ルールとして共有リポジトリへ公開せず、プロジェクト内の方針と回帰テストに留める。
- 全テストの1回目で既存 Task 入力テストが停止。`sample` のスタックは UITextField の becomeFirstResponder → UIKit paste support → PBServerConnection の同期 XPC 応答待ちで、Today の計算処理ではなかった（`/tmp/pocket-today-app-sample.txt`）。実行を中断し、Simulator のデータを消さず再起動。同一コードの再実行で当該入力テストと単体33件が成功した。環境復旧のために入力処理やアプリ仕様を変更していない。

### 2026-09-22 — 最終検証

- 詳細画面を開いている間に予定枠を過ぎた場合にも対応するため、フォーカス ID の変化ではなく、表示日の pending Task の結果確定を位置調整の条件にした。11時の未確定 Task を16時の画面から記録した後、17時の次 Task が中央へ戻る UI 回帰テストを追加。
- 再開直後の UI 実行で、中央の Task へのタップが詳細遷移に届かない失敗が1件発生。画像・アクセシビリティ階層では行が中央にあり、遮蔽物は確認できなかった。原因は確定していない。同じコードでの対象テスト再実行と、その後の全テストでは再現せず、待ち時間の追加やアプリのタップ処理変更は行っていない。
- 対象 UI テスト2件成功: `/tmp/pocket-today/Logs/Test/Run-TechAssistantPocket-2026.09.22_12-07-19-+0900.xcresult`。成功時の画面画像を `/tmp/pocket-today-final-images/` に抽出し、375pt・日本語・Accessibility XL の次 Task 表示と、完了後の中央表示を目視確認。
- 最終コマンド: `xcodebuild clean build test -project TechAssistantPocket/TechAssistantPocket.xcodeproj -scheme TechAssistantPocket -destination 'platform=iOS Simulator,id=F5AAAF6B-4297-43B8-B161-F42B0E6E9D2E' -derivedDataPath /tmp/pocket-today -parallel-testing-enabled NO`。
- クリーンビルド成功、単体33件 / 8 suites 成功、操作 UI 6件 + 起動4件 = UI 10件成功（失敗0）。結果: `/tmp/pocket-today/Logs/Test/Run-TechAssistantPocket-2026.09.22_12-09-06-+0900.xcresult`。Simulator 上でアプリ起動・操作を実施。Task 作成/編集/Archive、Review、Insights、通常 Event 作成、権限拒否の既存テストも成功。
- 最終差分を今回の2件の範囲で確認し、`git diff --check` 成功。ユーザーの DEVELOPMENT_TEAM 差分を保持。コミット・push は実施していない。
- 実機の Apple / Google 祝日カレンダー情報、同期後の再取得、手動スクロールを含む最終操作感は未検証。今回の Simulator 成功は実機・アカウント検証を代替しない。

## 2026-09-22 — 実機フィードバック第二弾（Home v2）

### 準備・仕様判断

- 第一弾の未コミット差分と既存 DEVELOPMENT_TEAM 設定を引き継ぎ、README / DESIGN / DEVELOPMENT_KNOWLEDGE / CLAUDE / Review Request / WORKLOG / UI資料、Task / Occurrence / Repository / Store / Calendar / Insights / 入力画面 / 既存テストを確認。GitHub の open Issues 取得は空。共有知識の AI 開発原則・小さい変更・日本語狭幅レイアウトを参照し、Web/CSS や新規ライブラリは適用しない。
- ユーザー添付の正式 Home モックを `docs/ui/TechSecretaryPocket_Today_Home_v2.jpg` に元のJPEGのまま保存。既存SVGを削除せず、UI READMEに今回の優先資料として記載。
- 開始済み枠の日時変更と「旧予定を残さない」の競合を説明し、ユーザーから「既存仕様を維持し、旧枠は履歴として残す」と回答。旧枠missed、新枠pending、Task ID不変、CalendarとInsightsの履歴保持を維持する。
- 未スケジュール再出現の原因は、Task本体が再利用可能な行為の定義であり、`unscheduledTasks` が pending の枠を持たない全active Taskを返すこと。データを削除・自動確定せず、Homeから一覧を外しTasksに管理を残す。

### 実装

- Today: 現在Taskの大きいカード（カテゴリ文字・タイトル・開始終了・残り時間・スキップ／完了）、次の時系列一覧、閉じた履歴・期限超過未確定、Review。現在Taskが重なる場合は開始順の先頭をカードとし、他のTaskと通常Eventも保持する。現在判定の終了境界は第一弾と完了判定に合わせて含む。
- スキップは明示的な選択シート。日時変更は既存ScheduleEditor、完了は既存ExecutionEditor、削除は確認後の既存Archiveを再利用。Archive済みの開始済み枠はHomeのメインから履歴へ移すが結果・保存履歴を変えない。
- 表示日の左右スワイプと前後日ボタンは同じdayを変更する。UIKitの方向判定をSwiftUIの小さいジェスチャーに限定し、縦スクロールとの同時認識を許可。確定時には横80pt以上・縦の1.8倍超を要求。日付計算はCalendarの日単位加算。
- カテゴリ候補は全Taskから読み取り、使用履歴をUserDefaultsへ保持。前後空白を除去し完全一致で重複排除。旧カテゴリを使うTaskがなくなっても候補を保持する。
- TaskEditorでpending枠を選択して日時編集可能にした。複数枠はPickerで対象を明示。追加／変更でScheduleFieldsを共有し、StoreのsaveTaskで一度のローカル保存とミラー・通知更新を調整。開始前の日時なしへの変更は枠とミラー・通知を取り除く。開始済み・確定履歴を日時なしにして消すことは許可しない。
- Task / TaskOccurrence / ReviewRecord schema、完了判定、InsightsEngine、CalendarReadPolicy、通常Eventの保存処理には第二弾の変更なし。DB移行・外部依存・commit・pushなし。

### 検証中の診断

- 初回ビルド成功。新規4件を含む単体37件 / 9 suites成功。カテゴリと完了状態のディスク再オープン、予定編集と日時解除、ミラー削除失敗再試行、旧枠のInsights維持、重なるTaskとEvent、日付ジェスチャー方向を検証。
- 初回UIで標準confirmationDialogのキャンセルが検出できないケースがあり、ユーザーの3選択肢を確実に示すsheetへ変更。横スワイプの再実行で認識しないケースを検出し、方向を判定するネイティブジェスチャーへ修正。
- 日時Toggleのテストは右側の実コントロールを操作して検証。履歴の展開後にListが上側の行を再利用で外すため、スクロールヘルパーを上下に探索できるよう修正。テストを弱めず、最終的に対象が操作可能なことを要求する。
- 接続済みiPhone 16 Proを検出したが、Xcodeの実機準備は「ロック解除が必要」のエラー。ユーザーに解除を依頼し、Simulator検証を継続。

### 2026-09-23 — 再開後の修正と検証

- 前回終了時の全UI13件の結果は2件失敗（権限拒否時の初回Tasksタブ移動、折りたたみ履歴の操作可能性）。成功扱いにせず画像・階層・イベント記録を確認した。
- 履歴は画面上に表示されても、巨大なDisclosureGroup内の行で操作可能性の判定が安定しなかった。見出しボタンと独立したList行による展開に変更し、履歴の取り出し・完了後のフォーカス・タブ復帰時の位置保持の回帰テストが成功した。
- 初回タブ移動はジェスチャー調整だけでは直らず、現在/次がない空のHomeへ `scrollTo(todayStart)` していた経路を外すと移動が成立した。フォーカス対象が存在する場合の中央表示は維持。スワイプは表示中のHome範囲を背景UIViewから監視し、コントロール・タブバー・モーダル操作を除外する。
- 375pt / Accessibility XL の画像で、固定径リング内の残り時間の省略とボタン内の不自然な改行を検出。アクセシビリティ文字サイズでは残り時間を通常のTextにし、ボタンを縦に配置。通常サイズはリングと横並びを維持する。
- 深夜再開により、Homeだけ16時固定・編集は実時計という既存fixtureのずれを確認。明示的な `--ui-testing` + `--ui-today-focus` の場合だけStoreの操作時刻も揃えた。通常利用はDate()のまま。日時変更画面の既存の未来日付制限も共有部品に保持。
- タブ移動確認後、SimulatorがTextField操作のidle待ちで停止。前回プロセスが残っている状態で次の検証を起動したため、今回の2本を明示終了し、データを消さずSimulatorを再起動。単一の全テストへ戻した。停止原因をTask保存ロジックの不具合とは断定しない。
- 実機は再接続できたがUIテストターゲットの署名チームとprofileが未設定だった。既存アプリのTeamをコマンド引数で渡して開発profileを準備。project.pbxprojは変更していない。その後codesignがSecurityサービスの署名キー利用応答待ちとなり、Mac上の許可をユーザーへ依頼。パスワードやキーを読み取らず、アクセス制御も変更しない。

### 2026-09-23 — 再開後の追加診断

- 全テストの回収結果はビルド成功、単体37件成功、UI13件中2件失敗。先の空画面scrollTo除去後の単発成功だけでは初回タブ移動の解決を確認できておらず、上記の診断を訂正する。
- 振り返りの失敗は、テストが説明文の「未確定」を未処理Taskと誤認し、存在しない「できなかった」ボタンを探していたため。対象操作ボタンの存在で分岐するよう修正。
- 横スワイプ監視を無効にした比較実行で権限拒否時の初回Tasks移動と追加が成功。監視先をUIWindowからHomeのListのUIScrollViewへ限定し、タブバーのタッチを監視対象から外した。
- 大きい文字の画像で標準borderedボタンのラベル表示が崩れていたため、明示的なHStackの文字・記号と角丸背景へ変更。文字サイズは制限せず、アクセシビリティサイズで縦配置する。

## 2026-09-24 — Claude CodeへのGitHub引き継ぎ整理

- ユーザーの最新依頼により、現在の未コミット作業を完成・検証し、commit / pushしてcleanかつremote同期済みにすることが明示的に許可された。先のcommit / push禁止はこの引き継ぎ作業について更新された。
- 実際のbranchは `feature/mvp-complete`、開始HEADは `b570bbae976ae49d13dc5c1b473d250f30b26cd5`。fetch後のorigin同branchも一致、ahead/behind 0/0、stagedなし。第一弾と既に進行中だったHome v2・編集・カテゴリの差分を保持。新規候補には着手しない。
- project / scheme / app・unit・UI targetsをxcodebuildで再確認。README・DESIGNに残っていたHomeの未スケジュール表示説明を現行実装へ揃えた。CLAUDE.mdに引き継ぎ参照、build/test、主要制約を追加し、`docs/CLAUDE_HANDOFF.md` に構成・仕様・検証・候補の実装済み/未着手区分を記載。
- タブ移動失敗はListへの監視限定後も一度再現しており、ジェスチャーだけを原因と断定しない。診断ログで監視先がHomeのUpdateCoalescingCollectionViewであることを確認。同じコードの再実行では最初のタブ移動が成功した。診断用NSLogは除去。
- 続く入力停止をsampleで調査し、UITextField becomeFirstResponder → Pasteboard PBServerConnection → 同期XPC応答待ちを確認 (`/tmp/pocket-handoff-app-sample.txt`)。今回のテストプロセスだけを停止し、Simulatorの保存データを消さず再起動。テストや機能の無効化では回避しない。
- 差分レビュー: Task / TaskOccurrence / ReviewRecord と InsightsEngine / SuggestionEngine は変更なし。既存署名Team2行を保持。秘密キー・トークンの既知形式検査に該当なし。DEBUG fixtureは明示UIテスト時だけ使用。未使用のTaskAction分岐を除去し、実験コード・診断ログを製品差分に残さない。
- Knowledge Review: タブ操作の不定期失敗は原因未確定、Simulatorのペーストボード応答待ちは環境依存。一般的なルールやライブラリとして公開せず、再現条件・検証限界をプロジェクト内へ記録する。

### 最終検証結果

- `xcodebuild build test -project TechAssistantPocket/TechAssistantPocket.xcodeproj -scheme TechAssistantPocket -destination 'platform=iOS Simulator,id=F5AAAF6B-4297-43B8-B161-F42B0E6E9D2E' -derivedDataPath /tmp/pocket-home-v2 -parallel-testing-enabled NO` がexit 0、BUILD / TEST SUCCEEDED。
- 単体37件 / 9 suites成功。CalendarReadPolicy、TodayPresentation、編集・カテゴリ永続化、既存Review/Insights/Calendar/通知の回帰を含む。UI操作9件＋起動4件＝13件成功、失敗0。以前失敗したCalendar拒否時の初回タブ移動とReviewも成功。
- 結果: `/tmp/pocket-home-v2/Logs/Test/Run-TechAssistantPocket-2026.09.24_20-13-31-+0900.xcresult`。ログ: `/tmp/pocket-handoff-validation.log`。画像を `/tmp/pocket-handoff-final-images` に抽出し、375pt日本語の通常/Accessibility XLでカード・スキップ/完了・文字欠けがないことを目視確認。
- テスト開始後のSwiftソースhash不変、`git diff --check`成功。実アカウントのEventKit取得/同期、通知の実機配信は未検証であり、fixtureの成功とは区別して引き継ぐ。実機署名待ちの制約も資料に記載。

## 2026-09-24 — 修正第二弾の依頼照合と追加仕上げ

- ユーザーが再度第二弾の完了を依頼。現在のHEAD `9b0276f`・clean状態と実コードを確認。Home/skip/スワイプ/カテゴリ/日時編集は既に実装済みであり、未完了機能として作り直さない。
- 接続先確認ではiPhoneがunavailable。ユーザーが「確認はシミュレートで大丈夫」と指定したため、実機再接続を待たずSimulatorと単体テストで進める。実アカウントの同期・通知配信を成功したとは扱わない。
- 現在Taskしかない場合、カードを除外する前の配列で判定していたため「次の予定」の空表示が出なかった。実際の次の予定配列で判定するよう修正。
- TaskEditorは既存枠の長さをUIへ読み込んでいたため、Taskの推定所要時間と枠長が異なると、タイトルだけの編集でも推定値を書き換えていた。また分への丸めによって開始済み枠の不要なrescheduleになる可能性があった。Stepperの明示操作を初期読込と区別し、操作していなければTask推定値・正確な枠長を別々に保持する。
- 回帰用DEBUG fixtureとUIテストを追加。推定10分・予定30分でタイトル編集後に予定を解除しても推定10分を保持すること、開始済み30分30秒枠のタイトル編集が保存できpendingを維持すること、現在TaskだけのHomeで空表示が出ることを確認する。
- 新規UIテスト初回は、日時付きTaskのアクセシビリティ名が「タイトル、日時」となるため完全一致の要素取得に失敗。実際の名前に合うタイトルprefixの照合へ修正し、検証を継続。製品処理の成功とは混同しない。
- `docs/HOME_V2_VALIDATION.md` に元の20項目と確認手段・既存仕様・検証限界を整理。
- 追加回帰fixtureは深夜直後でも現在Taskが前日所属にならないよう、開始時刻の下限を当日の開始へ揃えた。製品の日付所属ルールは変更しない。全体検証後にこのfixtureを使うUIテストを再確認する。
- 追加仕上げを含む `xcodebuild build test` がexit 0、BUILD / TEST SUCCEEDED。単体37件 / 9 suites、UI操作10件＋起動4件＝14件成功（失敗0）。結果: `/tmp/pocket-home-v2/Logs/Test/Run-TechAssistantPocket-2026.09.24_20-41-51-+0900.xcresult`、ログ: `/tmp/pocket-second-wave-final.log`。
- 全体テスト開始時のSwiftファイルhashと比較し、変更は追加fixtureの深夜対策のみ、製品コードに変更なしと確認。所要時間保持と現在TaskのみのHome画像を目視確認。Simulatorの過去のstatus bar時刻固定を解除し、追加fixtureの該当テストを最終再実行。
- Knowledge Review: 編集用状態の初期化とユーザーによる変更を区別し、別々のモデル属性を暗黙に同一値へ書き戻さない。このプロジェクトの具体例と回帰テストとして記録し、共有ルールや新ライブラリには広げない。
- 深夜対策後の追加UI回帰も成功（1件、失敗0、exit 0）。結果: `/tmp/pocket-home-v2/Logs/Test/Test-TechAssistantPocket-2026.09.24_20-50-26-+0900.xcresult`。Simulatorのstatus bar固定解除を実行した。status barの時計表示は時刻判定の検証根拠にせず、アプリの予定データ・ドメインテストで確認する。秘密キー・トークンの既知形式検査は該当なし、最終差分にDB/Engine/署名設定の変更なし。

## 2026-09-25 — 第三弾（日時・カテゴリ・生活日）

### 準備

- 実HEAD a3e2c2e、feature/mvp-complete、開始時clean。README→DESIGN→DEVELOPMENT_KNOWLEDGE、CLAUDE、UI資料、Task/Occurrence/Repository/Store/Calendar/Insights/Suggestion/設定/入力/テストを確認。open Issuesは0件。
- dev-knowledgeのdevelopment-principles、ai-development、mobile-japanese-layout-wrapping、raw-input-facts-not-game-semantics、project-startを取得。プロジェクト優先、小さい差分、入力状態と意味の分離、狭幅日本語の縦配置を適用。Web/CSSやゲーム固有コードは導入しない。共有リポジトリのtreeも確認し、生活日・カテゴリ集約・内容dedupeに直接対応する既存項目は見つからなかった。
- 変更前に全build/testを実行。build成功、単体37件/9 suites成功、UI14件中13件成功。権限拒否時の初回Tasksタップが失敗（既存ログにもある）。結果 `/tmp/pocket-home-v2/Logs/Test/Run-TechAssistantPocket-2026.09.25_01-58-02-+0900.xcresult`。ログ `/tmp/pocket-six-fixes-baseline.log`。

### 変更と判断

- ScheduleEditorの「開始済みなら現在+1時間へ置換」を除去。一度だけ保存日時を読込み、未変更ならrescheduleせず元枠を維持。明示的な日時変更は旧枠missed+新pendingという承認済み仕様を維持。正確な枠長とnilを含む通知も保持。
- 時刻選択はDateTimeFields/ClockFieldsを共通化。日付は日付Picker、時・分は即時Binding更新のMenu。Task追加/編集/予定変更/通常Event/実行記録/生活時間で使用。実行の未来時刻は保存不可を維持。
- 新規Taskだけ通知初期値0分。既存予定は保存値、既存Taskへの追加予定はSettings既定値を使用。Settingsに適用範囲を明記。
- CalendarReadPolicyの内容キーは正規化title+start+end+isAllDay+正規化location。IDを含めない。空白・Unicodeを正規化し、大文字小文字/句読点は保持。Storeの取得/空き時間双方で既知/削除待ちミラーを先に除き、通常予定を誤って消さない。EventKit正本は変更しない。
- CategoryAnalyticsEngineは値型TaskInput/OccurrenceRecordからカテゴリ別集約。全履歴を維持、未設定は未分類。Home/Tasks/Reviewのカテゴリ見出しを上位にし、Insightsはカテゴリ一覧/詳細/実行件数。曜日/時間帯3観測未満はデータ不足。Task状態・成功定義は変更なし。
- Suggestionは同カテゴリのTaskID集合を学習母集団にし、対象枠の長さを維持。根拠/改善幅/空き時間/承認は維持。生活時間変更時は再計算し、適用直前にも枠が新しい生活時間に収まるか検証。
- LifeDayPolicyはFoundationのみ。起床から就寝の半開区間、日跨ぎ、現在生活日、前後日を共通化。睡眠中は次の生活日、同時刻設定不可。Home/Calendar取得、Insights週・曜日、Suggestion条件で利用。DSTはCalendar日加算で扱う。設定はUserDefaultsの2整数、未設定ユーザーに一度だけ案内。
- Reviewの保存済み暦日キー/無効化は維持して対象暦日を明示。SwiftData schema/Task再生成/署名設定/外部依存は変更なし。履歴時点のカテゴリや生活時間を別保存する変更も行わない。

### 途中検証

- build成功、追加後の単体44件/10 suites成功（生活日境界、DST、深夜Homeと曜日/週の一致、カテゴリ集約、新Taskへのカテゴリ提案、個別完了、設定永続化と即時再取得）。
- 新規UIの深夜Home/生活時間変更/カテゴリ表示・データ不足、セットアップ保存後再起動は成功。375ptの画像を目視確認。新規通知0分も成功。
- 日時UI検証では通知PickerのAXラベル指定と、60項目Menuの未表示30分の探索を修正。選択後に余分な操作を挟まず保存する検証は維持。再開後はその手前の初回Tasksタップが失敗し、成功扱いにしていない。
- タブ失敗の合成イベントは(188,615)、AXのTasks枠は(141,588,94,54)で座標は適切。動画の該当フレームでもTasks領域と一致したがTodayに留まった。原因は未確定。診断目的だけでタブ実装を変更せず、全件で再確認する。


### 第三弾の最終検証・Knowledge Review

- 全build/testのbuild成功、単体45件/10 suites成功、UI18件中17件成功。新規4UIは全件成功。結果 `/tmp/pocket-home-v2/Logs/Test/Run-TechAssistantPocket-2026.09.25_09-37-42-+0900.xcresult`。
- 既存のCalendar拒否時の初回Tasksタップのみ失敗。全体実行終了後、専用Simulatorをデータを消さず再起動。同一コードの該当テスト再実行は成功（1件/exit 0）。結果 `/tmp/pocket-home-v2/Logs/Test/Test-TechAssistantPocket-2026.09.25_09-50-06-+0900.xcresult`。単一runの全件成功や根本原因解消とは表現しない。
- 画像 `/tmp/pocket-six-final-images/` で21:30と15分前通知の保持、カテゴリ主見出し、生活日9/24の翌00:30Task、375pt/Accessibility XLのHome/Tasks/Insightsを確認。全体テスト開始後のSwift hash不変。diff checkと既知形式の秘密情報検査成功。
- Knowledge Reviewを `docs/REVISION_3_VALIDATION.md` に記載。LifeDayPolicyはライブラリ昇格候補（固定生活時間・DST/睡眠中の方針に制約）。CalendarReadPolicy全体はプロバイダー検証不足、CategoryAnalyticsEngineはPocketの成否意味に依存するためProject内に留める。ミラー除外→内容dedupeの順序、読取集約と個別更新の分離はPattern候補。Context/Problem/Solution/Why/Limitations/Validation/Originを記載。共有リポジトリへの公開・コピー・外部依存追加は行わない。
- GitHub fetchで開始HEADとorigin/feature/mvp-completeが一致（ahead/behind 0/0）を確認。以前のユーザー指定のGitHub共有方針に従い、今回の完成差分・資料をcommit/pushし、最終状態を別途確認する。
