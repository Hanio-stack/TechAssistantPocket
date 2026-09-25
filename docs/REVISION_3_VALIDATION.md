# 日時・カテゴリ・生活日 — 第三弾

更新: 2026-09-25。6項目の実装とSimulator検証を完了。

## 原因と変更

| 項目 | 原因 / 変更 |
|---|---|
| 開始日時のリセット | ScheduleEditorが過去の開始を現在+1時間へ置換していた。保存値を一度だけ読み込み、未変更保存で予定枠を動かさない |
| 分の確定 | 従来のcompact DatePickerによる編集確定に依存。日付と時・分のMenu選択を分け、Date Bindingを即更新する共通DateTimeFieldsへ変更 |
| Calendar重複 | 旧方針はcalendar/event ID/startの完全一致のみ。同内容が異なるアカウントにあれば残っていた。タイトル・開始・終了・終日・場所の内容キーへ変更 |
| 新規通知 | 新規Taskも任意の既定通知（未設定ならnil）を読み込んでいた。Task新規時だけ0分、既存枠は保存済み通知を保持 |
| カテゴリ | 一覧・Insights・提案がTask単位だった。全Taskのカテゴリで履歴を集約。状態変更は個別のまま |
| 生活日 | Home/取得/分析が暦日基準だった。LifeDayPolicyを共有し、起床〜就寝範囲・現在日・曜日・週を統一 |

## 互換性と意図した制約

- Task / TaskOccurrence / ReviewRecordのschema・成功判定・Archive・通知/Calendarの責務は維持。DB移行・履歴削除・Task再生成なし。
- 開始後の日時変更は旧枠missed、新枠pendingという承認済みの既存仕様。旧Calendar枠も履歴として保持する。
- カテゴリ未設定は「未分類」。現在のTaskカテゴリで過去履歴も再集計する。履歴時点のカテゴリを別保存する機能は追加しない。
- 新規Taskの通知は0分。既存Taskへ予定を追加する場合はSettingsの既定値を使用する。
- 就寝は排他的境界。睡眠中は次の生活日を表示。起床と就寝の同値は不可。睡眠中の過去実行も分析から消さず次の生活日として集計する。
- 生活時間を変えると過去の曜日・週の集計も新設定で再計算する。時刻そのものは書き換えない。
- Reviewは保存済み暦日のまま互換性を維持し、Homeに対象暦日を明示する。
- 内容キーが完全一致する独立予定も表示上は1件になる。元Calendarは変更しない。識別子・アカウントが違うという理由だけでは分割しない（今回の明示仕様）。

## 途中の検証

- 変更前: build成功、単体37件成功。UI14件中13件成功。Calendar拒否時の初回Tasksタブ移動が失敗。過去ログにもある問題で、今回の変更前に再現。
- 単体追加後: build成功、44件 / 10 suites成功。
- 新規UI: 深夜Home/設定変更/カテゴリ表示、生活時間セットアップの保存後再起動が成功。日時・通知は要素指定を修正し再検証中。

## Knowledge Review

指定の開発原則・AI開発ルール・日本語狭幅レイアウト・入力事実とアプリ意味の分離・project-startを確認。既存構造の保全、Foundation値型、明示的な入力Binding、狭幅で縦配置する方針を適用。ゲームの速度サンプルやWebのCSS自体は導入しない。

全テストの回収と画面確認を踏まえ、以下を共有候補として評価した。dev-knowledgeへのコピー・公開は行っていない。

## 再利用・共有化の評価候補

### LifeDayPolicy — 共有ライブラリへ昇格する候補

- Context: 起床日を日ラベルにするローカル日付処理をHomeと分析で共有する。
- Problem: 深夜・週境界・夏時間で画面ごとの日付計算が食い違う。
- Solution: 起床/就寝の分値とCalendarを受け、半開区間・日ラベル・前後日を返す純粋値型。
- Why: 永続化やUIに依存せず、同じ入力が同じ判定になる。
- Limitations: 固定の毎日時刻が対象。曜日別勤務・履歴時点の設定・旅行時の過去タイムゾーン固定は扱わない。睡眠中は次の生活日という方針、DST解決方針も利用先で合意が必要。
- Validation: 起床/就寝境界、深夜、同日就寝、週境界、DST23/25時間相当のテストが成功。Home/設定UIも成功。最終検証結果は末尾を参照。
- Origin: TechAssistantPocket、2026-09-25、実機フィードバック第三弾。

分類はPattern候補。共有するなら `Sources/LifeDayPolicy/` + `Tests/LifeDayPolicyTests/` + `README.md` + `docs/pattern.md` を一組にした小さいSwift Packageを提案する。今回、外部Package作成・コピー・同期は行わない。

### CalendarReadPolicy — 全体はProject内に留める

- Context: 複数アカウントの同内容予定とPocketミラーが混在する。
- Problem: 内容dedupeを先に行うと代表にミラーが選ばれ、後からそのミラーを除いて通常予定も失う。
- Solution: 識別子による除外を先に行い、その後に正規化内容キーでdedupeする。
- Why: 表示の同一性とアプリ固有の除外理由は別であり、除外順序が結果を変える。
- Limitations: 祝日判定はEventKitメタデータのヒューリスティック。実アカウント/未対応言語は検証不足。完全に同内容の独立予定も表示上は統合される。
- Validation: 内容キーの違い、時刻違い、個人終日、祝日、ミラーと同内容の通常予定、Store経由の取得をテストする。元Eventの変更なし。
- Origin: TechAssistantPocket、2026-09-25、Calendar重複修正。

除外順序はPattern昇格候補。CalendarReadPolicy全体はまだProject固有なのでライブラリ昇格しない。将来は汎用の内容キー/除外パイプラインに限定し、入力値型・テスト・README/Patternを同梱する候補。

### CategoryAnalyticsEngine — Project内に留める

- Context: 具体的Taskごとでは履歴が不足し、同カテゴリから学習したい。
- Problem: 集約単位の変更とTask完了状態の変更を混同すると、他Taskまで解決される。
- Solution: TaskID→カテゴリの値型対応で読取集約し、既存Insightsの成否/観測計算を再利用する。更新操作は元Occurrence IDを指定する。
- Why: 保存モデルと履歴を移行せず集約単位だけ変更できる。
- Limitations: 現在カテゴリで過去も再集計する。success/missed/actualの意味はPocket固有。他製品での妥当性は未検証。
- Validation: 複数Taskの集約、分母除外、曜日/時間帯、履歴ゼロの新Taskへの提案、対象枠長の維持、同カテゴリ他Taskがpendingのまま残ることを確認。
- Origin: TechAssistantPocket、2026-09-25、カテゴリ中心の分析。

純粋ロジックとして独立テスト可能だが、まだProject固有なので共有ライブラリへ昇格しない。共有知識としては「読取集約と更新対象の分離」のPattern候補。共有リポジトリへは未公開。

## 依頼ケースと確認方法

| ケース | 確認 |
|---|---|
| 1–2 保存済み21:00、21:30へ変更して即保存 | testSavedTimeAndMinuteSelectionImmediatelySave。再編集で21:30を確認。開始済み19:00も未変更保存で保持 |
| 3–4 複数Calendarの内容dedupe・別時刻を保持 | CalendarReadPolicyTests。場所/終日属性の違い、ミラー除外順序も確認 |
| 5–6 新規通知0分、既存通知を保持 | testNewTaskReminderDefaultsToStart、日時UIで15分保持、Store単体でnil保持 |
| 7–8 カテゴリ集約・曜日/時間帯/実行数 | categoryAggregatesMultipleTasksWithoutChangingSuccessSemantics |
| 9 新Taskにカテゴリ履歴を利用 | newTaskUsesCategoryEvidenceButKeepsItsOwnDuration。別カテゴリを除外し、対象45分枠を保持 |
| 10 個別Task完了 | lifeSettingsPersistAndImmediatelyRefreshCalendarWithoutChangingHistory。同カテゴリ他枠はpendingのまま |
| 11–14 日跨ぎ・現在日・就寝境界・同日就寝 | overnightLifeDayBoundariesAndNavigation、lifeDayTimelineAndAnalyticsAgreeAfterMidnight |
| 15–16 設定即反映・深夜Calendar | lifeSettingsPersistAndImmediatelyRefreshCalendarWithoutChangingHistory、testLifeDayHomeCategoryAndSettingsRefresh |
| 17 祝日/mirror除外 | CalendarReadPolicyTests、TimelineTests、Storeの同内容通常予定保持 |
| 18 履歴保持 | 既存HomeEditingTestsのディスク再オープン、Category/Store単体、既存Review/Insights UI |
| 初回のみ生活時間設定 | testLifeSetupOnlyUntilSaved。保存後、同じdefaultsで再起動して非表示 |
| 狭幅・大きい文字 | 375pt日本語で既存Accessibility XLテストと新カテゴリ/生活日のスクリーンショットを確認 |

## 変更ファイルの役割

- 純粋計算: `LifeDayPolicy.swift`（新規）、`CategoryAnalyticsEngine.swift`（新規）、`CalendarReadPolicy.swift`、`InsightsEngine.swift`、`SuggestionEngine.swift`、`Timeline.swift`。
- 共通日時入力・生活時間設定: `DateTimeFields.swift`（新規）、`LifeHoursView.swift`（新規）、`TasksView.swift`、`EventEditor.swift`、`SettingsView.swift`、`ContentView.swift`。
- 状態・表示・Calendar取得: `PocketStore.swift`、`CalendarService.swift`、`TodayView.swift`、`InsightsView.swift`、`ReviewView.swift`。
- 検証: DEBUG限定`DebugFixtures.swift`・`TechAssistantPocketApp.swift`、`LifeDayAndCategoryTests.swift`（新規）、`CalendarReadPolicyTests.swift`、`TechAssistantPocketUITests.swift`。
- 資料: README、DESIGN、UI README、CLAUDE_HANDOFF、WORKLOG、本資料。
- 変更なし: Task/Occurrence/ReviewRecord schema、TaskRepository、NotificationService、project.pbxprojの署名設定。


## 最終検証結果

- `xcodebuild build test`でbuild成功、単体45件 / 10 suites成功。UI操作14件＋起動4件の18件中17件成功。変更前からあるCalendar拒否時の初回Tasksタップだけ失敗。
- 全体結果: `/tmp/pocket-home-v2/Logs/Test/Run-TechAssistantPocket-2026.09.25_09-37-42-+0900.xcresult`。ログ: `/tmp/pocket-six-fixes-full.log`。
- テスト専用Simulatorをデータを消さずshutdown/bootし、同じコード・同じ失敗テストを再実行。1件成功、exit 0。結果: `/tmp/pocket-home-v2/Logs/Test/Test-TechAssistantPocket-2026.09.25_09-50-06-+0900.xcresult`。ログ: `/tmp/pocket-six-fixes-tab-recheck.log`。
- 全18UIケースの成功を確認したが、単一の全体実行が全件成功したとは扱わない。初回タップの原因は未確定で、再起動後の成功を根本修正とは断定しない。
- 新規4UIケースは全体実行で全件成功。21:00→21:30の即保存・15分前通知保持、開始済み19:00の未変更保存、通知0分、深夜生活日/カテゴリ/設定即反映、セットアップの再起動後非表示を確認。
- 375pt日本語、通常文字とAccessibility XLの画像を `/tmp/pocket-six-final-images/` に抽出して目視確認。カテゴリ主見出し、個別Task小見出し、カテゴリ別Insights、時刻21:30/15分前通知、スキップ/完了の表示を確認。
- 最終テスト中のSwiftソースhash不変。`git diff --check`成功、既知形式の秘密情報検査は該当なし。Task/Occurrence/ReviewRecord/Repositoryと署名設定の差分なし。
- 実アカウントのEventKit/Google同期・実機通知配信は未検証。祝日メタデータの言語/プロバイダー差、保存済みReviewの暦日単位、現在設定で過去集計が変わる点は上記の制約として残る。

実行方法は `docs/CLAUDE_HANDOFF.md` を参照。同じSimulatorへ複数のxcodebuildを同時実行しない。
