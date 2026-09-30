# Auto Scheduler validation and Knowledge Review

更新：2026-09-30。**新UIの検証は進行中**。下記の検証済み範囲と未検証範囲を分けて扱う。

## Recovery and verified milestones

- `f3c826a`：旧Pocketのカードデッキ／時刻Wheelを安定化し、`feature/mvp-complete`へpush。build成功、単体48件、UI操作15件＋起動4構成が全体実行と該当再実行を通して成功。
- `07c6913`：WorkWindowPolicy / SchedulePackingEngine / TaskSelectionEngine。build＋単体58件成功。
- `e9f01c1`：追加Backlog情報・提案・操作事実の保存。build＋単体61件成功。旧DB→新schema→新操作→再オープンを検証。
- `acb3a9e`：StoreとCalendar bridgeの統合。build＋単体68件成功。13:00の180分提示→15:20完了→30分読書、Skip再候補、再起動、Calendar失敗と再試行を検証。

## UI investigation

最初の新UI作成テストで、テキスト欄をタップした後に応答が止まった。検証用プロセスのsampleでは、UIKitの `uncachedDelegateSupportsImagePaste` → Pasteboard XPCの同期応答待ちがメインスレッドを占めていた。SchedulerやSwiftData保存の呼び出しはその停止スタックにない。専用Simulatorをデータ消去せず再起動し、同じアプリコードで再検証中。製品コードにdelay/retry/強制Tab selectionは追加していない。

旧Tab初回移動のflaky testとこのPasteboard待機は別の観測。根拠なく同じ原因として扱わない。

## Knowledge Review

### Work-window and interval-selection core — shared-library candidate

- **Context**：端末内で、作業可能時間と外部予定から今できる仕事を選ぶ。
- **Problem**：日跨ぎ、曜日切替、Busy重複、残り時間、Skip直後の再表示をViewごとの条件分岐にすると不整合になる。
- **Solution**：ローカル時刻のWorkWindowPolicy、DateInterval差分のSchedulePackingEngine、値型候補のTaskSelectionEngineへ分離する。Clock、Calendar、現在時刻は明示的な入力。
- **Why**：外部Calendar provider、SwiftData、SwiftUIを知らずに境界例と優先順を検証でき、選出理由を説明できる。
- **Limitations**：1曜日区分1区間。休日は土日。開始日の曜日を使用し、重なる前日／当日区間は前日を終了まで優先。分割Task・将来の大量packing・preemption・最適化・祝日切替は未対応。既提示枠の保持はStoreの責務。
- **Validation**：平日／休日、前中後、日跨ぎ、Busy clip/merge、優先度/FIFO、5/30/180分境界、早い完了後の再選出、Skip除外の単体・統合テスト成功。
- **Origin**：TechAssistantPocket、`07c6913`、`AutoSchedulingCore.swift` / `AutoSchedulingCoreTests.swift`。

共有する場合の一組：`Sources/LocalSchedulingCore`（LifeDayPolicyを含むFoundation値型）、`Tests/LocalSchedulingCoreTests`、`README.md`（Usageと境界の意味）、`docs/Pattern.md`（上記7項目）。まずAPI・DST・複数区間の要求を別プロジェクトで評価してからPackage化する。現時点で外部コピーや依存は追加しない。

### Observations versus inferred work — Pattern candidate

- **Context**：Taskの提示・完了・Skipから履歴を自然に得たい。
- **Problem**：提示から完了までの時間を作業時間とみなすと、休憩や別作業を事実として誤保存する。
- **Solution**：提案枠の割当メタデータとTaskActionRecordの操作事実を別に持つ。分析にはproposedAt/occurredAt/kindの値型だけを渡し、差分時間を導出しない。
- **Why**：観測したことだけを保存し、Calendar表示の長さと測定事実を混同しない。
- **Limitations**：作業時間の測定・生産性評価はできない。操作時刻は実行開始時刻でもない。旧実績の意味を新記録へ読み替えない。
- **Validation**：action schemaにactual/elapsed/durationフィールドがないこと、操作時刻と提示時刻の保存、再オープン、旧履歴保持をテスト。
- **Origin**：TechAssistantPocket、`e9f01c1` / `acb3a9e`、TaskActionRecord、SchedulerPersistenceTests。

`dev-knowledge/patterns/raw-input-facts-not-game-semantics.md`と原則が重複する。新しい一般原則として重複追加せず、必要なら既存Patternの適用例として提案する。

### Calendar ownership and retry — project-local

- **Context**：外部予定を読んで、自分で作った予定だけ再同期する。
- **Problem**：単なるタイトル照合や保存済みIDへの無条件上書きは通常予定を変更し得る。外部保存とDB保存の間には中断点がある。
- **Solution**：proposal UUIDをURLマーカーへ付け、更新前に所有権を検証。再試行時にマーカーで再発見し、外部保存後にローカル同期状態を確定する。
- **Why**：一般予定を変更せず、二重作成を抑える。外部失敗でもユーザーの完了操作は保存済みにできる。
- **Limitations**：EventKit実アカウントのID変化・複数端末・Google等のURL保持は実機未検証。旧未タグのミラーは自動削除しない。プロバイダーをまたぐ完全なトランザクションではない。
- **Validation**：fixture上のID衝突・所有タグ・再試行・read/write failure・mirror除外を検証。既存CalendarReadPolicyテストも実行。
- **Origin**：TechAssistantPocket、`acb3a9e`、SchedulerCalendarBridge / EventKitAdapter / AutoSchedulerStoreTests。

実機プロバイダー検証が不足するため共有ライブラリへ昇格しない。CalendarReadPolicy全体も祝日メタデータのヒューリスティックに依存するためProject内に留める。

### Action analytics and SwiftUI components — project-local

ActionAnalyticsEngineは操作件数と操作時刻の曜日／時刻帯を集計する。Pocketのcompleted/skippedという意味を含むため、汎用化はまだ行わない。Home、CompactTimePicker、Swipe表示は狭幅・Dynamic Type・Reduce Motionの検証結果を確認してから再利用性を判断する。未検証のUIを共有リポジトリへコピーしない。

## Applied shared knowledge

- development-principles：小さな安全地点、Coreの単体テスト、外部依存の境界、実際の差分と実行結果を正とする。
- ai-development：仕様・既存実装・テストを先に読む。buildだけで利用フローの正常を主張しない。
- mobile-japanese-layout-wrapping：日本語見出しと内容は縦へ伸ばし、狭幅や大きい文字で操作を到達可能にする。
- raw-input-facts-not-game-semantics：Drag入力とcomplete/skipの意味、提案／操作の観測事実と作業時間の推測を分離する。

今回、dev-knowledgeへの公開・コピーは行っていない。検証済みCoreは候補としてProject内に記録し、未検証の外部連携は昇格しない。
