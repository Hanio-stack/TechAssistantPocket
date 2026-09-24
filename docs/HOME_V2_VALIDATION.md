# Home v2 — 修正第二弾の確認

2026-09-24。元の修正依頼を現在のコードへ照合。ユーザーの「確認はシミュレートで大丈夫」に従い、Simulatorと単体テストを検証対象とする。実アカウント・実機でしか確認できない同期・通知配信は、成功したとは扱わない。

## 実装の対応

- 現在Taskを大きいカードで表示し、カードの操作はスキップ/完了のみ。カテゴリは文字で表示し、絵文字・一時停止・メモ欄を追加しない。
- 次のTask/通常Eventを時系列表示。完了・終了済みと期限超過pendingを別々に閉じて表示し、Homeには未スケジュールTaskを再掲しない。
- スキップは選択シート。日時変更は同じTaskへ既存reschedule、削除は確認付きArchive、キャンセルは無変更。
- 左右スワイプと前後日ボタンは同じ表示日を更新。横80pt以上・縦の1.8倍超を条件とする。
- カテゴリ候補はTask履歴とUserDefaultsへ保持し、空白除去と重複排除。編集済みTaskの日時を同じ入力部品から変更できる。
- 正式モック: `docs/ui/TechSecretaryPocket_Today_Home_v2.jpg`。

## 今回見つけた不足と補正

1. 現在Taskしかない場合も内部のupcoming配列にはそのTaskが含まれるため、「次の予定」の空表示が出なかった。カードのTaskを除外した実際の一覧で空判定する。
2. Task本体の推定所要時間と予定枠の長さが異なる場合、編集画面の初期化で読み込んだ枠長がタイトル編集時にも本体へ書き戻されていた。明示的な所要時間操作と初期読込を区別し、タイトル/カテゴリ/日時だけの変更では元の推定値を保持する。
3. 予定枠を分単位UIへ読み込んだだけで秒の端数を切り落とすと、開始済み枠のタイトル編集が意図しないreschedule扱いになる。所要時間を操作しなければ元の正確な枠長を保存する。

## 主な変更ファイル

- `TodayView.swift` / `Timeline.swift`: カード・一覧・日付・状態別表示。今回の追加は次の予定の空判定。
- `TasksView.swift`: カテゴリ選択、共通日時入力、既存Taskの編集。今回の追加は明示的な所要時間操作の識別。
- `PocketStore.swift` / `TaskRepository.swift`: カテゴリ履歴、同じTaskの保存・予定移動・開始前の日時解除。今回の追加変更なし。
- `DebugFixtures.swift` / `TechAssistantPocketApp.swift` のDEBUG部分 / UIテスト: 編集属性保持と空表示の回帰ケース。
- `HomeEditingTests.swift` / `TodayPresentationTests.swift` / `CalendarReadPolicyTests.swift`: 永続化・予定移動・表示・第一弾の回帰根拠。
- README / DESIGN / WORKLOG / CLAUDE_HANDOFF / 本資料: 現行仕様と確認結果。

ファイルの場所はアプリが `TechAssistantPocket/TechAssistantPocket/`、テストが隣の `TechAssistantPocketTests/` と `TechAssistantPocketUITests/`。DBモデル・InsightsEngine・署名設定は今回変更していない。

## 元の20項目と確認手段

U = Simulator UIテスト、D = ドメイン/永続化単体テスト、V = 画像・実コード確認。UIテストは隔離したfixtureで実行し、実ユーザーのCalendarを書き換えない。

| # | 依頼の確認項目 | 確認手段 |
|---|---|---|
| 1 | 17–18時Taskを17:30に現在Taskと判定 | D: HomeEditingTestsの固定日時。U: 現在Taskカード表示 |
| 2–5 | スキップ/完了のみ、一時停止・メモ・カテゴリ絵文字なし | U: current card / skip flow、V: 通常文字・Accessibility XL画像とView |
| 6 | 完了後、既存処理で記録し次の予定を表示 | U: TodayFocusAndHistory、D: TodayPresentationTests |
| 7–8 | 翌日などへ日時変更、Taskと有効予定が重複しない | U: skip→ScheduleEditor→保存、D: HomeEditingTestsの翌日移動とID/枠数 |
| 9 | スキップ→削除、確認とキャンセル | U: HomeSwipeSkipCancelRescheduleAndDelete、D: Archive回帰 |
| 10–11 | 左右で表示日を前後、元の日付へ戻る | U: HomeSwipeSkipCancelRescheduleAndDelete |
| 12 | 縦スクロールで日付が変わりにくい | D: 縦移動・斜め移動の閾値、U: 履歴を縦スクロールして同日のTaskを操作 |
| 13–14 | 使用済カテゴリを再選択、新規入力も可能 | U: ReusableCategoryAndTaskEditorSchedule、D: trim・重複排除 |
| 15–16 | Task編集で日時設定、同じTask/予定へ反映 | U: 編集画面の日時設定・再表示、D: 開始前の移動/解除/再設定とミラー・通知 |
| 17 | 昨日完了したTaskを翌日Homeへ未スケジュールとして再掲しない | D: ディスク再オープン後の翌日presentation、V: Homeに未スケジュール一覧がない |
| 18 | 祝日除外・通常予定保持・履歴・現在/次の回帰 | D: CalendarReadPolicyTests / TodayPresentationTests、U: TodayFocusAndHistory |
| 19 | Insightsの集計を変えない | D: 既存InsightsAndSuggestionTestsと開始済み旧枠の分母検証。Engineコード変更なし |
| 20 | 再起動相当でもカテゴリ・Task状態を保持 | D: 実ファイルのSwiftData containerを閉じて再作成、UserDefaultsも再読込 |

追加回帰: Task推定10分・予定30分のタイトル編集→未来予定解除→編集画面で10分維持。開始済み30分30秒枠のタイトル編集が保存でき、pendingのままであることをUIで確認する。

## 維持する仕様・検証限界

- 開始済みの日時変更は、ユーザー確認済みの「旧枠missed＋同じTaskの新pending」。旧Calendar/Insights履歴が残るのは意図した仕様。Archiveも開始済み・確定履歴を消さない。
- Taskの現在判定は既存完了判定と同じ終了境界を含む。通常Eventは終了境界を含まない。
- DB schema・migration・完了判定・Insights集計を変更しない。
- iCloud/Googleの実際の同期遅延、実機通知、実アカウントの祝日メタデータはこのSimulator検証の対象外。
- 日時入力UIの接続はUIテストで確認し、保存された日時・一意性・ミラー/通知の値は単体テストで検証する。全てのDatePicker操作を自動操作したとは扱わない。

## 今回の検証結果

2026-09-24、375pt iOS Simulator（Pocket MVP Narrow / iOS 26.3.1）で実行。

- `xcodebuild build test` 成功、exit 0。
- 単体 **37件 / 9 suites成功**。CalendarReadPolicy / TodayPresentation / HomeEditing、既存Insights・Review・Calendar/通知境界を含む。
- UI操作 **10件＋起動4件＝14件成功、失敗0**。今回の属性保持・現在Taskのみの空表示も含む。
- 全体結果: `/tmp/pocket-home-v2/Logs/Test/Run-TechAssistantPocket-2026.09.24_20-41-51-+0900.xcresult`。
- 追加回帰の画像で推定10分の保持、長い日本語タイトルの現在カード、次の予定なし表示を確認。
- 製品コードは全体検証後変更なし。深夜の開始日所属を考慮したDEBUG fixtureの調整後、該当UIテストを再実行して成功。結果: `/tmp/pocket-home-v2/Logs/Test/Test-TechAssistantPocket-2026.09.24_20-50-26-+0900.xcresult`。
- DBモデル・完了判定・Insights・Calendar処理・署名設定の差分なし。`git diff --check` 成功。

実行方法は `docs/CLAUDE_HANDOFF.md` のTests節。ログとxcresultは一時成果物であり、再現手順と結果をリポジトリへ保存する。
