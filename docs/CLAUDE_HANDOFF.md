# Claude Code / Fable handoff

更新: 2026-09-24。最初にこの引き継ぎを読み、README → DESIGN → DEVELOPMENT_KNOWLEDGE → 関連コード・テスト・実際のGit状態を確認する。

## Project

TechAssistantPocket は iPhone 向けの行動改善型スケジューラ。Plan → Do → Review → Improve → Plan を端末内で完結させる。Swift / SwiftUI、SwiftData、EventKit、UserNotifications。バックエンド・LLM API・追加外部依存はない。

今後は Claude Code / Fable が主な実装担当、GPT / Astra が仕様設計・レビュー・複雑な問題の検討を担当する。GitHub の commit 済み状態を正式な共有状態とし、ローカルだけの変更を引き継ぎ完了と扱わない。

## Current branch

- branch: `feature/mvp-complete`
- remote: `origin` = `https://github.com/Hanio-stack/TechAssistantPocket.git`
- 整理開始時の local / remote HEAD: `b570bbae976ae49d13dc5c1b473d250f30b26cd5` (`Complete TechAssistantPocket MVP`)
- 完成版実装 commit: `f8aa84d77918e06318995d369dcd6ebb571a72e6` — `Complete calendar filtering and Home task workflows`。この実装に対して下記の全テストが成功。
- この資料自体を含む最新 commit は `git log -1 --format='%H %s'` で確認する。資料内に自己参照するハッシュを固定せず、作業開始時に `git fetch origin` と `git status -sb` で同期状態を再確認する。

## Completed in this handoff

整理開始時点の未コミット差分には、第一弾だけでなく、先に依頼され実装中だった第二弾も含まれていた。以下は既存の進行中作業を完成させたもので、新規候補への着手ではない。

- Calendar の読み取り専用祝日カレンダー除外、同一 calendar / event ID / start の重複抑制。通常の別予定・別の繰り返し回は保持。
- Today の現在・次、折りたたみ履歴、期限超過 pending の分離。時間経過だけで missed にしない。
- 現在 Task カード、スキップ / 完了、日時変更 / 確認付き Archive、表示日の左右スワイプと前後日ボタン。
- Home の未スケジュール一覧を削除。Task は再利用可能な定義であり、pending 枠がなくなると従来の未スケジュール一覧に戻っていた。履歴は消さず管理を Tasks に集約。
- 使用済みカテゴリの選択・新規入力。全 Task のカテゴリと UserDefaults `taskCategoryHistory` を統合し、前後空白除去・完全一致重複排除。最後の使用 Task を編集しても候補を保持。
- Task 編集から pending 枠の日時・所要時間・通知を編集。複数枠なら対象を選択。開始前だけ日時なしに戻せる。日時入力は `ScheduleFields` を共有。
- DEBUG 限定 fixture、Calendar / Today / 編集・永続化テスト、UI 回帰テスト、仕様・作業ログ整合。
- ユーザーが既に設定していたアプリの DEVELOPMENT_TEAM を保持。署名キー・profile はリポジトリに含めない。

正式 Home 参照は `docs/ui/TechSecretaryPocket_Today_Home_v2.jpg`。添付はJPEGだったため元形式で保存した。古いSVGは履歴資料として保持。

## Important architecture

アプリコードは `TechAssistantPocket/TechAssistantPocket/` 配下。

| ファイル | 責務 |
|---|---|
| `CalendarService.swift` | EventKitAdapter による取得・書き込み、権限、保存先確認。読み取り predicate に対象カレンダーを渡す。対象0件を nil（全件）に戻さない |
| `CalendarReadPolicy.swift` | Foundation の純粋なメタデータ判定・重複排除。Today と空き時間判定に適用 |
| `Timeline.swift` | TaskOccurrence record と通常Eventの統合、ミラー除外、現在/未来・未確定・履歴、focus/currentTask、スワイプ方向の判定 |
| `TodayView.swift` | 上記 presentation の描画、必要時のみ中央スクロール、日付状態、既存編集画面への導線。スワイプ監視はHomeのListに限定 |
| `Task.swift` / `TaskOccurrence.swift` | 再利用可能な Task 定義と各予定・実行履歴。状態遷移の正本 |
| `TaskRepository.swift` | SwiftData 保存・取得、reschedule、Archive、Review無効化、開始前の予定解除 |
| `PocketStore.swift` | UI共有状態、Repository / Calendar / Notification の調整。ローカル保存後の同期と削除再試行、カテゴリ履歴 |
| `TasksView.swift` | Task一覧・詳細、TaskEditor、共有ScheduleFields、ScheduleEditor、ExecutionEditor |
| `InsightsEngine.swift` / `SuggestionEngine.swift` | 純粋Foundation集計と説明可能な提案。今回の集計変更なし |
| `InsightsView.swift` | 今週成功率・Task一覧とTask別の曜日/時間帯詳細。今回変更なし |

Task は SwiftData が正本、Calendar はミラー。通常Eventは EventKit が正本でReview・成功率に含めない。Pocket Task の通知は UserNotifications のみ、通常Eventは Calendar Alarm。

## Important constraints

- DB schema / migration を勝手に変更しない。今回も移行なし。
- 完了操作は実際に開始した時刻を記録する既存処理。success は開始〜終了の両端を含む。現在 Task の判定も `scheduledStart <= now <= scheduledEnd` の pending（Archive除外）。通常Eventの終了は含まない。
- 複数の現在Taskは開始順の先頭をカードにし、残りは一覧に残す。日付またぎTaskは開始日所属。
- スキップは新状態ではない。キャンセルは変更なし、日時変更は既存reschedule、削除は既存Archive。
- **ユーザー確認済み**: 開始前の変更は同一枠更新。開始後の変更は旧枠missed + 同じTaskの新pending。旧Calendar枠・Insights履歴は残す。「古い予定を消す」ためにこの意味を変更しない。
- Archiveは未来pendingだけ削除。開始済み・確定履歴を保持し、pendingを勝手に確定しない。
- Insights成功率 `success / (success + missed)` を無関係なUI変更で触らない。pending/cancelled/予定なし実行は分母に含まない。
- Calendar読み取りフィルタと書き込み先選択は別責務。Taskミラーや書き込み可能な個人Calendarを祝日フィルタで消さない。
- 表示日変更はデータ複製・書き換えをしない。縦スクロールとの誤判定を避けるため横80pt以上かつ縦の1.8倍超を条件とする。
- 大規模設計変更・外部依存・サーバー・CloudKit・戻しにくい移行はユーザー確認。未依頼の候補を実装しない。
- `--ui-testing` 等はDEBUG専用。in-memory DB・fixture・固定時刻を製品実行に混ぜない。

## Tests

Xcode project: `TechAssistantPocket/TechAssistantPocket.xcodeproj`。scheme: `TechAssistantPocket`。targets: 同名アプリ / `TechAssistantPocketTests` / `TechAssistantPocketUITests`。

```sh
xcodebuild -list -project TechAssistantPocket/TechAssistantPocket.xcodeproj
xcrun simctl list devices available
# DEVICE_ID は自分の環境のSimulator UUIDに置き換える
xcodebuild build test \
  -project TechAssistantPocket/TechAssistantPocket.xcodeproj \
  -scheme TechAssistantPocket \
  -destination 'platform=iOS Simulator,id=DEVICE_ID' \
  -derivedDataPath /tmp/pocket-validation \
  -parallel-testing-enabled NO
```

単体だけなら `-only-testing:TechAssistantPocketTests` を追加。実機は有効な開発署名・端末準備が必要。同じSimulatorへ複数のxcodebuildを同時実行しない。

主要テスト:

- `CalendarReadPolicyTests`: Apple/Google系メタデータ、個人終日・非祝日購読の保持、別Calendar・繰り返しを誤統合しない。
- `TodayPresentationTests` / `TimelineTests`: 終了境界、日付所属、DST、ミラー除外、未確定と履歴、結果確定時のfocus。
- `HomeEditingTests`: 日時編集と一意性、ミラー・通知、開始済み旧枠、Insights維持、カテゴリと履歴のディスク再オープン、17–18時Taskの17:30表示、重なり・スワイプ閾値。
- `ReviewAndRescheduleTests` / `InsightsAndSuggestionTests` / `ServiceCoordinationTests` / `PlatformPayloadTests`: 既存ドメイン・分析・プラットフォーム境界の回帰。
- UI: 狭幅375pt・日本語・大きい文字、現在Task/完了/履歴、skip・日付スワイプ、カテゴリ・日時編集、Calendar拒否、Review/Insights/Event、起動。

今回の最終検証（2026-09-24）:

- `xcodebuild build test` 成功、exit 0。
- 単体 **37件 / 9 suites 成功**。CalendarReadPolicy / TodayPresentation / HomeEditingを含む。
- 操作UI **9件**＋起動 **4件** = **13件成功、失敗0**。初回Tasksタブ移動・Reviewのケースも成功。
- 375pt日本語・通常文字とAccessibility XLの最終スクリーンショットを目視確認。スキップ/完了の文字欠けを解消。
- `git diff --check` 成功。テスト開始後のSwiftソースhashは不変。
- ローカル結果bundle: `/tmp/pocket-home-v2/Logs/Test/Run-TechAssistantPocket-2026.09.24_20-13-31-+0900.xcresult`。ログ: `/tmp/pocket-handoff-validation.log`。これら一時成果物はGit管理せず、再現手順と結果をこの資料・WORKLOGに保存する。

## Known issues / validation limits

- 実アカウントのEventKit取得・Google/iCloud同期はSimulator fixtureでは証明できない。実機署名はMacのSecurityサービスの応答待ちで完了しておらず、実機テスト成功とは扱わない。
- 公開EventKit APIに一般的な祝日フラグがない。改名・未対応言語・opaqueなIDの祝日Calendarは残る場合がある。未知の読み取り専用Calendarを一律に隠さない。
- 再試行待ちのCalendar削除はSettingsで再試行。SwiftDataの保存成功と外部Calendar同期成功は別。
- UI検証で初回タブ移動の不定期失敗を観測。ジェスチャーの接続先は実ログでHomeのCollectionViewと確認したが、単発成功だけで原因を断定しない。最終の全件実行では成功。再発時はTests欄の手順で環境と製品動作を切り分ける。
- SimulatorのTextField入力停止をsampleで調査し、UIKit becomeFirstResponder → PBServerConnection → 同期XPC応答待ちを確認。テスト停止・データを消さないSimulator再起動で環境復旧する。テストの無効化や仕様変更で回避しない。
- 実機の通知配信、各アカウントの祝日メタデータ、Calendar同期後の再取得は引き続きlive確認が必要。

## Next candidates（追加実装は行わない）

ユーザーが挙げた候補を、現在の実装と取り違えないこと。

| 候補 | 現在の状態 / 次に行うなら |
|---|---|
| Home中央の現在Task、スキップ/完了 | 今回の既存差分で実装済み。次は実機で操作感の確認 |
| スキップから日時変更/削除 | 実装済み。旧枠履歴の確認済み仕様を保持 |
| Home右→左で翌日 | 実装済み。実機で縦スクロールとの競合確認 |
| Task編集から日時変更 | 実装済み。実Calendar・通知同期を実機確認 |
| 使用済カテゴリの再選択 | 実装済み。再起動後の実機確認 |
| Insightsの簡素化 | 現状も1ページ目は週成功率＋Task一覧、詳細に曜日・時間帯を表示。追加の変更は差分を確認してからユーザー依頼で行う。今回変更なし |

**推奨する最初の作業は1つ**: 引き継いだcommitを実機でbuildし、既存Calendarアカウントを使ったHome・日時変更・同期のスモークテストを実施して結果を記録する。新規機能の実装を始める前に残るlive検証を完了する。
