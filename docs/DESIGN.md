# TechAssistantPocket 設計・ユーザーフロー

最終更新: 2026-09-24

## 1. 何を作るか

TechAssistantPocket は、単なる Todo / Calendar アプリではなく、**ユーザーの実行履歴から「その人が予定を成功させやすい条件」を見つけ、次の予定改善につなげる iOS アプリ**とする。

コアサイクル:

```text
Plan
予定を決める
↓
Do
実行する
↓
Review
予定どおりできたか / 実際はいつできたかを確認する
↓
Improve
曜日・時間帯の傾向から次回の予定を改善する
↓
Plan
```

### MVP の原則

- 運用コスト 0
- Local First
- OpenAI API / LLM API なし
- 自前サーバーなし
- Google Calendar API 直接連携なし
- AI に見える部分は説明可能なルールベース
- 機能追加よりコアループ完成を優先
- アプリがユーザーの予定を勝手に変更しない

---

## 2. ユーザーが扱うものは 2 種類だけ

### 2.1 Task

「自分が達成したいこと」。例: 英語学習、ジム、BK 制作、読書。

- 完了 / 未完了を記録する
- 予定した時刻と実際に実行した時刻を記録する
- Review / Insights の対象
- 日時を設定した場合は EventKit にカレンダーイベントを作る
- **正本は Pocket (SwiftData)**

### 2.2 Event

「その時間にある予定」。例: 映画、食事、美容院、会議、病院。

- 完了 / 未完了を聞かない
- 成功率に含めない
- Review の対象外
- Today と空き時間判定には使う
- Pocket から追加する場合も EventKit に直接保存する
- **正本は Calendar (EventKit)**

### 2.3 追加導線

画面を増やさず、`+` からだけ分岐する。

```text
+ 追加
  ├─ Task
  │   └─ やることを追加
  └─ 予定
      └─ 映画・食事・約束など
```

---

## 3. MVP の範囲

### 必須

- Task 作成 / 編集 / 削除
- 未スケジュール Task
- Task の日時、所要時間、通知
- 通常 Event の追加
- Today 画面
- Task と Event の時系列表示
- Task の完了 / 未完了記録
- 実際に Task を実行した時刻の記録
- iPhone カレンダー参照
- 選択したカレンダーへの Task / Event 登録
- 選択済みカレンダー消失時の再選択
- ローカル通知
- Today から行うデイリーレビュー
- 曜日 / 時間帯 / Task ごとの傾向
- 今週の予定成功率
- ルールベースのスケジュール提案

### MVP では持たない

- Task の優先度
- 独立した Review タブ
- OpenAI API / LLM API
- チャット UI
- 自然言語タスク登録
- 自前バックエンド
- Google Calendar API 直接連携
- 複雑な全自動スケジューリング
- チーム / 他ユーザー共有
- 高度な機械学習
- 完全な Calendar 双方向同期

Task の優先度は現時点で並び替え・通知・提案のどれにも使わないため削除する。必要になった段階で追加する。

---

## 4. 初回起動フロー

1. アプリの目的を短く説明
2. EventKit の権限を要求
3. 端末上の利用可能なカレンダーから既定保存先を 1 つ選ぶ
4. 通知権限を要求
5. Today へ

Google Calendar を使いたいのに候補がない場合は、iPhone 側に Google アカウントのカレンダーを追加するよう案内する。

---

## 5. Task 作成フロー

最低入力はタイトルのみ。

```text
タイトル       必須
日時           任意
所要時間       任意
通知           任意
カテゴリ       任意
```

### 5.1 日時なし

```text
Task
↓
SwiftData のみ
↓
未スケジュールとして保持
```

未スケジュール Task では所要時間を未設定のまま保存してよい。

### 5.2 日時あり

日時を設定した場合、所要時間の初期値は **30 分** とする。ユーザーは変更可能。

```text
Task
↓
TaskOccurrence を作成
↓
scheduledStart = 選択日時
scheduledEnd = scheduledStart + 所要時間
↓
CalendarService
↓
EventKit にミラーイベントを作成
↓
必要なら NotificationService で通知予約
```

Pocket 由来のカレンダーイベントは Task の正本ではない。

### 5.3 既存 Task に予定を追加する

履歴を Task 単位で継続して分析できるよう、同じ行為を予定するたびに新しい Task を作らない。

Tasks 画面から既存 Task を選択し、`予定を追加` できるようにする。

例:

```text
Tasks
↓
英語学習
↓
予定を追加
↓
日時 / 所要時間 / 通知
↓
既存 Task.id に新しい TaskOccurrence を追加
```

これにより「英語学習」の履歴が同一 Task に蓄積される。

### 5.4 未スケジュール Task を予定なしで実行した場合

未スケジュール Task を実際に行った場合も、実行履歴を残す。

```text
既存 Task
英語学習

scheduledStart = nil
scheduledEnd = nil
planResult = nil
actualExecutedAt = 実際に開始した時刻
```

このとき新しい `TaskOccurrence` を 1 件作成する。

予定成功率には含めず、「実際に行動できた曜日 / 時間帯」の観測として利用する。

完了後に記録する場合も `actualExecutedAt` は完了ボタンを押した時刻ではなく、ユーザーが実際に開始した時刻を保存する。入力の初期値は現在時刻でよいが、必要ならおおよその開始時刻へ修正できるようにする。

### 5.5 Task の削除

ユーザー操作上の「削除」は、MVP では原則として **Archive** として扱う。

```text
Task を削除
↓
Task.archivedAt を設定
↓
過去の TaskOccurrence は保持
↓
未来の pending TaskOccurrence だけ削除
↓
対応するローカル通知を削除
↓
対応する Calendar ミラーを削除
```

削除対象となる未来の予定は、`planResult == pending` かつ `scheduledStart > 現在時刻` の TaskOccurrence とする。

`success / missed / cancelled` など確定済みの履歴、および現在時刻以前に属する TaskOccurrence は残す。これにより Task を今後使わなくなっても過去の Insights 履歴は失わない。

---

## 6. 通常 Event 作成フロー

`+ → 予定` を選択。

```text
タイトル
開始日時
終了日時
保存先カレンダー
通知
```

保存先は EventKit のカレンダー。通常 Event のため SwiftData に Task は作らない。

---

## 7. Today

Today はアプリのホーム。

```text
現在のタスク（大きいカード）
英語学習  [スキップ] [完了]

次の予定
12:00    友達と昼食
15:00  □ MPC練習
18:30    映画

完了・終了済み / 時間を過ぎた未確定（折りたたみ）
```

- Task: チェックボックスあり
- Event: チェックボックスなし
- Pocket Task の EventKit ミラーは二重表示しない
- `TaskOccurrence.calendarEventIdentifier` と一致する EventKit Event は通常 Event 一覧から除外する

### 7.1 今 / 次を中心に表示する

- 通常一覧は現在進行中・未来の Task / Event を開始時刻順に統合する。
- 結果確定済みの Task (`success / missed / cancelled`) と終了済み Event は、初期状態で閉じた「完了・終了済み」に表示する。保存済み履歴は削除しない。
- 終了時刻を過ぎても `pending` の Task は、別の「時間を過ぎた未確定」に残す。時間経過だけで結果を確定せず、従来どおり実行記録・予定変更・Review から扱う。
- 「今」は未確定 Task の `scheduledStart <= now <= scheduledEnd`、Event の `start <= now < end`。現在の時刻付き項目がなければ、最初の未来の時刻付き項目を「次」とする。Task の結果判定の終了境界は従来どおり含む。
- 個人の終日予定も保持して同じ時系列に表示するが、フォーカスは時刻付きの行動を優先する。未スケジュール Task の管理は Tasks に置き、Home には表示しない。
- 初回表示・表示日変更・表示日の Task の結果確定時に、今 / 次の行を可視領域の中央へスクロールする。予定枠を過ぎてから記録した場合も含む。通常の再取得・時間経過・同日への復帰だけでは手動の閲覧位置をリセットしない。
- 日付は端末のローカル Calendar で判定する。日付またぎ Task の所属は開始日のまま。Event は表示日と重なるものを扱う。現在日を表示中は日付変更に追従する。


### 7.2 Home v2（実機フィードバック第二弾）

- 正式 UI 参照は `docs/ui/TechSecretaryPocket_Today_Home_v2.jpg`。現在の Task を最も大きいカードにし、カテゴリ（文字のみ）、タイトル、開始〜終了、残り時間、スキップ / 完了を表示する。位置・メモ等のフィールドは追加しない。
- pending かつ開始〜終了内の Task をカードにする。第一弾と完了判定との整合のため終了境界を含む。重複時は開始順の先頭 Task をカード、その他 Task / 通常 Event を時系列一覧に保持する。現在 Task は通常 Event よりフォーカスを優先する。
- Home の未スケジュール一覧を廃止。Task 本体は再利用する行為の定義であり、完了は TaskOccurrence に記録される。pending がない Task は Tasks で再予定できるが、翌日 Home へ未スケジュールとして再表示しない。
- スキップは状態名ではなく選択導線。日時を変更 / Taskを削除 / キャンセルを提示する。完了は既存の実際の開始時刻の記録画面を使用する。
- 日時変更は既存 reschedule を使用。開始前は同一枠更新、開始後は旧枠 missed + 同じ Task の新 pending 枠（ユーザー確認済み）。旧枠は Calendar / Insights の履歴として保持し、有効な予定を複製しない。
- 削除は確認後に既存 Archive を使用する。開始済み枠と確定履歴は残し、アーカイブ済み Task の枠は Home の通常一覧・現在カードには出さず履歴内に保持する。開始済み pending の結果を削除だけで自動確定しない。
- 横移動80pt以上かつ縦移動の1.8倍を超えるスワイプだけで表示日を前後1日変更。前の日 / 明日を見る（別日では次の日）も同じ日付状態を変更する。日付加算はローカル Calendar を使用。表示切り替えによる Task 書き込みはしない。

### 7.3 Task 編集とカテゴリ

- カテゴリ候補は全 Task（Archive 含む）のカテゴリと、UserDefaults `taskCategoryHistory` の使用履歴を統合する。前後空白を除去し、完全一致で重複排除。最後の Task のカテゴリを変更しても以前の名前を保持する。SwiftData schema の変更・移行はない。
- Task 編集は pending の予定枠の日時・通知・所要時間を表示する。複数枠がある場合は変更対象を選ぶ。確定履歴を自動選択して編集しない。日時UIは予定追加 / 予定変更と共有する。
- 日時変更時は既存 Repository.reschedule を使用する。日時なし→ありは同じ Task に枠を追加。開始前の pending だけ日時なしへ戻せる（その枠を削除、通知・ミラーも削除し、連携失敗は既存キューで再試行）。開始済みを日時なしに戻して履歴を消す操作は許可しない。
- 保存後はストアを再取得し Calendar ミラー・通知を更新。旧枠の開始時刻が過去でも、タイトル・カテゴリのみの保存で reschedule や missed 確定を起こさない。

---

## 8. 「予定」と「実行」を分けて記録する

Pocket が知りたい事実は 2 つ。

1. **その時間に置いた予定は機能したか**
2. **実際にはいつ Task を実行できたか**

`actualExecutedAt` は **実際に Task を開始した時刻** と定義する。完了時刻ではない。MVP では実際の終了時刻は保存しない。

例:

```text
英語学習
予定: 10:00-11:00
実際: 18:00

→ 10時の予定は missed
→ 18時に実行できた事実は actualExecutedAt として残す
```

### 8.1 planResult の意味

```text
pending
success
missed
cancelled
```

- `pending`: 予定済みだが結果未確定
- `success`: `actualExecutedAt` が `scheduledStart ... scheduledEnd` の枠内
- `missed`: 予定した枠内では実行できなかった
- `cancelled`: 実行不要になった

### 8.2 確定ルール

- `scheduledEnd` を過ぎただけでは `pending → missed` に自動遷移させない
- `planResult` はユーザーの完了操作、再スケジュール操作、または Review で確定する
- `scheduledEnd` 後に完了した場合は `missed + actualExecutedAt`
- `cancelled` は成功率の分母・分子から除外する

### 8.3 例

予定どおり:

```text
予定 10:00-11:00
実行 10:30
planResult = success
actualExecutedAt = 10:30
```

後で実行:

```text
予定 10:00-11:00
実行 18:00
planResult = missed
actualExecutedAt = 18:00
```

完全に未実行:

```text
planResult = missed
actualExecutedAt = nil
```

予定なしの自発実行:

```text
scheduledStart = nil
scheduledEnd = nil
planResult = nil
actualExecutedAt = 18:00
```

---

## 9. 予定変更の扱い

### 予定開始前に変更

失敗ではない。同じ `TaskOccurrence` の `scheduledStart / scheduledEnd` を更新する。

### 予定開始後に変更

元の予定はすでに失敗したと扱う。

```text
旧 TaskOccurrence
10:00 → missed

新 TaskOccurrence
18:00 → pending
```

ユーザーが明示的に再スケジュールせず、単に後で実行した場合は、旧 TaskOccurrence を `missed + actualExecutedAt` とする。

---

## 10. デイリーレビュー

Review は独立タブにしない。Today の中で必要になった時だけ表示する。

### 10.1 「その日」の定義

Task の所属日は **`scheduledStart` のローカル日付**。

例: 23:00 開始、翌 1:00 終了の Task は開始日の Task とする。

予定なし Task は日次 Review の対象集合に含めない。

### 10.2 Review を出す条件

その日に予定 Task が 1 件以上あり、次のどちらかを満たしたら Today 下部に Review 導線を出す。

1. その日の予定 Task がすべて `success / missed / cancelled` のいずれかに確定した
2. その日の最後の Task の `scheduledEnd` を過ぎ、未確定 Task が残っている

その日に予定 Task が 0 件なら Review を出さない。

日付をまたぐ Task がある場合、翌日に Review 導線が出ても対象日は開始日側とする。現在日付が変わっている場合は `昨日を振り返る` と表示する。MVP では未レビュー日が複数ある場合、直近 1 日分だけ提示する。

### 10.3 Review 完了後に同日へ Task が追加された場合

**Review は再び必要な状態に戻す。**

例:

```text
18:00 その日の Review を完了
20:00 同じ日付に 22:00「読書」を追加
↓
その日の ReviewRecord を未確定扱いに戻す
↓
22:00 の Task が解決する、または scheduledEnd を過ぎる
↓
Review 導線を再表示
```

理由: 後から追加された Task が `pending` のまま残り、成功率の分母から漏れることを防ぐため。

実装上は、Review 完了後に同じ `dateKey` へ新しい予定 Task を追加した時点で、その日の Review 完了状態を無効化する。ReviewRecord を削除するか、同等の「再レビュー必要」状態に戻す方法でよい。

### 10.4 Review で行うこと

未確定 Task だけ確認する。

```text
英語学習
10:00 に予定していました

○ 予定どおりできた
○ 後でやった
○ できなかった
○ キャンセルした
```

`後でやった` を選んだ場合だけ、実際のおおよその時刻を入力する。

---

## 11. Insights

### 11.1 1ページ目

表示するのは 2 項目だけ。

```text
今週の成功率
72%
予定どおりできた割合

タスク別
英語学習  68% >
MPC練習   74% >
読書       45% >
BK制作     81% >
```

### 11.2 Task 詳細

- 成功しやすい曜日
- 成功しやすい時間帯
- おすすめ時間

### 11.3 2種類の分析

予定成功率:

```text
予定成功率 = success / (success + missed)
```

`cancelled / pending / 予定なし実行` は除外する。

時間帯適性:

- 予定どおりできた → 予定時間帯に成功 1
- 予定に失敗した → 予定時間帯に失敗 1
- 後で実行した → 実際の実行時間帯に成功 1
- 予定なしで実行した → 実際の実行時間帯に成功 1
- 同じ時間帯内で予定どおり実行した場合は成功を二重カウントしない

---

## 12. SuggestionEngine v0.1

高度な最適化は行わない。

候補を出す最低条件:

1. 同一 Task に一定数の履歴がある
2. 現在の曜日 / 時間帯に失敗傾向がある
3. 別の曜日 / 時間帯に成功観測が十分ある
4. Calendar 上で候補時間が空いている
5. 改善幅が明確

初期案では同条件 3 件以上を目安にする。ユーザーが承認した場合のみ予定変更を行う。

---

## 13. Calendar 設計

### 13.1 正本

```text
Pocket Task
正本 = SwiftData
Calendar Event はミラー

通常 Event
正本 = EventKit / Calendar
Pocket は表示・作成・編集の窓口
```

### 13.2 既定カレンダー

書き込み直前に保存済み `calendarIdentifier` がまだ利用可能か確認する。

```text
選択済みカレンダー
↓
まだ EventKit に存在する？
├─ YES → 使用
└─ NO
   ↓
「以前使用していたカレンダーが見つかりません」
   ↓
再選択
```

Calendar が消えても SwiftData 上の Task は失わない。

### 13.3 Google Calendar

MVP では Google Calendar API を使わない。

```text
Pocket
↓
EventKit
↓
iPhone に登録された Google Calendar
↓
Google と同期
```

### 13.4 双方向同期

完全同期は MVP では扱わない。

- Pocket Task を Pocket 内で編集した時は SwiftData を正として Calendar ミラーへ反映
- 通常 Event は EventKit の最新状態を表示
- ミラー Event が外部で削除されても Task は保持する
- ミラー Event が見つからない場合は identifier を解除し、必要なら再ミラー可能にする

### 13.5 通知の責務

通知の二重発火を防ぐため、Task と通常 Event で通知の責務を分ける。

- **Pocket Task**: 通知は `UserNotifications` のみで管理する
- Pocket Task の EventKit ミラーには Calendar Alarm を付けない
- **通常 Event**: ユーザーが通知を設定した場合は EventKit 側の Calendar Alarm として保存する

これにより同じ Task に Pocket 通知と Calendar 通知が重複して発火することを防ぐ。

### 13.6 祝日カレンダーの除外

- EventKit の読み取り時に祝日カレンダーを除外する。Today と空き時間判定に同じ読み取り方針を使う。通常 Event は SwiftData に取り込まないため、旧データの削除・移行は不要。
- 公開 API には汎用の祝日フラグや購読 URL がないため、読み取り専用かどうか、購読・アカウント種別、カレンダー名を組み合わせる。日本語・英語の既知の祝日カレンダー名、および取得できる場合の Google 祝日フィード識別子を対象にする。
- Event のタイトル（敬老の日など）や終日属性だけでは除外しない。編集可能な個人カレンダーと、祝日以外の購読カレンダーは残す。判定不能な改名済み・未対応言語のカレンダーは、個人予定を誤って隠さないため残す。
- 同じカレンダー・Event 識別子・開始時刻の重複は1件にする。タイトル一致だけで別カレンダーの通常予定を統合せず、繰り返し予定の別の回も保持する。祝日カレンダーが複数あっても、それぞれ取得対象から除外する。

---

## 14. データモデル v0.1

### Task

```text
id
title
category?
estimatedDuration?
createdAt
archivedAt?
```

優先度は持たない。

### TaskOccurrence

```text
id
taskID
scheduledStart?
scheduledEnd?
planResult?           // pending / success / missed / cancelled
actualExecutedAt?       // 実際に Task を開始した時刻
calendarEventIdentifier?
calendarIdentifier?
createdAt
```

### ReviewRecord

```text
id
dateKey
reviewedAt
```

Review 完了後に同じ `dateKey` へ新しい予定 Task が追加された場合、その ReviewRecord はその日の最新状態を表さなくなるため無効化し、再 Review を可能にする。

予定数・完了数などは TaskOccurrence から計算し、重複保存しない。

### App Settings

```text
defaultCalendarIdentifier
notificationDefaults
```

UserDefaults / AppStorage 等で十分なものは SwiftData モデルを増やさない。

---

## 15. 実装境界

大規模な Clean Architecture は採用しない。Apple API を View から直接ばら撒かない。

```text
SwiftUI
   ├─ TaskRepository ───── SwiftData
   ├─ CalendarService ──── EventKitAdapter
   ├─ NotificationService ─ UserNotifications
   ├─ InsightsEngine ───── 純粋ロジック
   └─ SuggestionEngine ─── 純粋ロジック
```

- TaskRepository: Task / TaskOccurrence の保存・取得
- CalendarService: Calendar 一覧、利用可否、Event 読み込み・作成・更新・削除
- NotificationService: Task 通知の登録・更新・削除
- InsightsEngine: 予定成功率、曜日 / 時間帯観測、Task 別集計
- SuggestionEngine: 履歴と空き時間から候補を返す。自分で Calendar は変更しない

---

## 16. 画面構成 v0.1

### Today

- 表示日を切り替えられる時間軸
- 現在 Task のカードとスキップ / 完了操作
- 次の Task / Calendar Event
- 折りたたみ履歴・期限超過未確定
- 条件成立後の Review 導線
- 未スケジュール Task の管理は Tasks に配置

### Tasks

- Task 一覧
- 未スケジュール
- 今後の Task
- Task 追加 / 編集
- 既存 Task を選択して `予定を追加`

### Insights

1ページ目:
- 今週の成功率
- Task 別一覧

Task 詳細:
- 成功しやすい曜日
- 成功しやすい時間帯
- 改善提案

### Settings

- 既定 Calendar
- 通知

Review は独立タブにしない。UI 基準は `docs/ui/` を参照する。

---

## 17. 主要エラーケース

### Calendar 権限なし

- Task 自体は作成可能
- Calendar 反映が必要な時に権限案内

### 既定 Calendar が消えた

- Task は保持
- Calendar 再選択を要求

### Calendar Event 作成失敗

- SwiftData の Task を消さない
- 再試行可能な状態を示す

### 通知権限なし

- 通知なしで利用継続

### Task の Calendar ミラーが見つからない

- Task は Pocket が正本なので保持
- 必要なら次回編集時に再作成可能

---

## 18. MVP テストで特に守るケース

### InsightsEngine

1. 10時予定 → 10時に成功
2. 10時予定 → 未実行
3. 10時予定 → 18時に後から実行
4. 予定なし → 18時に自発実行
5. cancelled は成功率から除外
6. pending は成功率から除外
7. 同じ時間帯で予定成功した場合に成功を二重計上しない

### Review

1. 予定 Task 0件の日に Review 導線が出ない
2. 23:00-翌1:00 の Task が開始日側の Review に所属する
3. 翌日に日付が変わった場合 `昨日を振り返る` に到達できる
4. Review 完了後に同日へ新しい予定 Task を追加すると、その日の Review が再び必要になる
5. 新しい Task が解決するか `scheduledEnd` 経過後に Review 導線が再表示される

### 予定変更

1. 開始前変更は失敗にしない
2. 開始後変更は旧予定を missed、新予定を新規 TaskOccurrence とする

### Task / TaskOccurrence

1. 日時あり Task は所要時間未指定時に 30 分を初期値とする
2. 既存 Task から `予定を追加` すると同じ Task.id に新しい TaskOccurrence が作られる
3. 未スケジュール Task の自発実行で `scheduledStart = nil / planResult = nil / actualExecutedAt = 実際の開始時刻` の TaskOccurrence が作られる
4. `actualExecutedAt` は完了操作時刻ではなく実際の開始時刻として保存される
5. Task を Archive しても過去の TaskOccurrence は保持される
6. Archive 時に未来の pending TaskOccurrence・通知・Calendar ミラーだけ削除される

### Calendar

1. 選択済み Calendar が存在する
2. 選択済み Calendar が削除済み
3. Pocket Task の Calendar ミラーを Today で二重表示しない
4. ミラー identifier が解決できなくても Task を失わない
5. Pocket Task の EventKit ミラーに Calendar Alarm を付けない
6. Pocket Task の通知は UserNotifications のみで 1 回発火する
7. 通常 Event の通知は EventKit の Calendar Alarm として保存する

---

## 19. MVP 完成条件

**1週間使った時に、次の流れが一周すること。**

```text
Task を作る
↓
日時を決める
↓
Calendar に反映
↓
通知
↓
実行 / 未実行を記録
↓
Today から Review
↓
Insights に傾向が出る
↓
次の時間を提案
↓
ユーザー承認で予定変更
```

通常 Event も同じ Today に表示できるが、評価対象にはしない。

---

## 20. 将来候補

- CloudKit 同期
- 繰り返し Task の高度化
- Google Calendar API 直接連携
- より高度な空き時間探索
- オンデバイス ML
- 自然言語入力
- 自動スケジューリング
- Task の優先度（実際に利用する機能が決まった場合のみ）

将来機能のために MVP の UI やデータモデルを先に肥大化させない。

---

## 21. 開発上の原則

- GitHub 上の仕様を正とする
- 実装前に `README.md` → `docs/DESIGN.md` → `docs/DEVELOPMENT_KNOWLEDGE.md` → 関連する `Hanio-stack/dev-knowledge` の順に確認する
- UI 実装では `docs/ui/` を参照する
- 大きな依存追加や戻しにくい変更は Human Gate を置く
- 実装 → Build → Test → 修正を自律ループさせる
- コアループに不要な新機能を MVP に追加しない
- Insights / Suggestion のロジックは Apple API から独立させ、Unit Test 可能にする
- 作業区切りで Knowledge Review を行い、再利用価値が確認できた知見だけ `dev-knowledge` / ライブラリ候補へ昇格する
