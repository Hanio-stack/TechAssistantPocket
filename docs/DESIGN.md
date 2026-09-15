# TechAssistantPocket 設計・ユーザーフロー

最終更新: 2026-09-15

## 1. 何を作るか

TechAssistantPocket は、単なる Todo / Calendar アプリではなく、**ユーザーの実行履歴から「その人が予定を成功させやすい条件」を見つけ、次の予定改善につなげる iOS アプリ**とする。

コアサイクルは以下。

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

「自分が達成したいこと」。

例:

- 英語学習
- ジム
- BK 制作
- 読書

Task は Pocket の分析対象になる。

- 完了 / 未完了を記録する
- 予定した時刻と実際に実行した時刻を記録する
- Review の対象
- Insights の対象
- 日時を設定した場合は EventKit にカレンダーイベントを作る
- **Task の正本は Pocket (SwiftData)**

### 2.2 Event

「その時間にある予定」。

例:

- 映画
- 友達と食事
- 美容院
- 会議
- 病院

Event は評価しない。

- 完了 / 未完了を聞かない
- 成功率に含めない
- Review の対象外
- Today には表示する
- 空き時間判定には使う
- Pocket から追加する場合も EventKit に直接保存する
- **Event の正本は Calendar (EventKit)**

### 2.3 追加導線

画面を増やさず、`+` からだけ分岐する。

```text
+ 追加
  │
  ├─ Task
  │   └─ やることを追加
  │
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

### Step 1: アプリの説明

短く目的だけ伝える。

> TechAssistantPocket は、あなたが予定を実行しやすい曜日・時間を実績から見つけ、次の予定を改善するアプリです。

アカウント作成は要求しない。

### Step 2: カレンダーアクセス

EventKit の権限を要求する。

許可されたら端末上の利用可能なカレンダーから、Pocket が Task を書き込む既定カレンダーを 1 つ選ぶ。

```text
予定を書き込むカレンダー

○ iCloud / 自宅
● Google / メイン
○ Google / 仕事
```

Google Calendar を使いたいのに候補がない場合は、iPhone 側に Google アカウントのカレンダーを追加するよう案内する。

### Step 3: 通知

通知権限を要求する。

通知を拒否してもアプリ自体は使用可能とする。

### Step 4: Today

初回設定後は Today へ。

---

## 5. Task 作成フロー

最低入力はタイトルのみ。

```text
新しい Task

タイトル       必須
日時           任意
所要時間       任意
通知           任意
カテゴリ       任意
```

カテゴリは将来分析に利用できるが、MVP では必須にしない。

### 日時なし

```text
Task
↓
SwiftData のみ
↓
未スケジュールとして保持
```

### 日時あり

```text
Task
↓
TaskOccurrence を作成
↓
CalendarService
↓
EventKit にミラーイベントを作成
↓
必要なら通知予約
```

Pocket 由来のカレンダーイベントは Task の正本ではない。

---

## 6. 通常 Event 作成フロー

`+ → 予定` を選択。

```text
新しい予定

タイトル
開始日時
終了日時
保存先カレンダー
通知
```

保存先は EventKit のカレンダー。

```text
Pocket
↓
CalendarService
↓
EventKit
↓
iCloud / Google / その他 iOS Calendar
```

通常 Event のため SwiftData に Task は作らない。

---

## 7. Today

Today はアプリのホーム。

Task と Calendar Event を同じ時間軸で表示する。

```text
10:00  □ 英語学習
12:00    友達と昼食
15:00  □ MPC練習
18:30    映画

未スケジュール
□ 本を読む
□ 部屋の掃除
```

- Task: チェックボックスあり
- Event: チェックボックスなし

Pocket Task を EventKit にミラーしているため、Today では二重表示しない。

TaskOccurrence に保持した `calendarEventIdentifier` と一致する EventKit イベントは、通常 Event 一覧から除外する。

---

## 8. 「予定」と「実行」を分けて記録する

Pocket が知りたいのは 2 つの事実。

1. **その時間に置いた予定は機能したか**
2. **実際にはいつ Task を実行できたか**

例:

```text
英語学習
予定: 10:00
実際: 18:00
```

この場合、次の両方を保存する。

```text
10:00 → 予定としては失敗
18:00 → 実際には英語学習を実行できた
```

「最終的に英語をやったから 10:00 も成功」とは扱わない。

### 8.1 予定どおり実行

```text
予定 10:00 - 11:00
実行 10:30

planResult = success
actualExecutedAt = 10:30
```

### 8.2 予定には失敗したが後で実行

```text
予定 10:00 - 11:00
実行 18:00

planResult = missed
actualExecutedAt = 18:00
```

この 1 件から、

- 10時台には失敗した
- 18時台には実行できた

という 2 つの観測を Insights に渡せる。

### 8.3 完全に未実行

```text
planResult = missed
actualExecutedAt = nil
```

### 8.4 予定なしで自発的に実行

```text
scheduledStart = nil
scheduledEnd = nil
planResult = nil
actualExecutedAt = 18:00
```

予定成功率には影響しないが、「実際に行動できた時間」の正の観測として利用できる。

### 8.5 Cancel

やる必要がなくなった Task は `cancelled`。

`cancelled` は成功率の分母・分子から除外する。

---

## 9. 予定変更の扱い

### 予定開始前に変更

例: 10時の英語を、9時の時点で18時へ変更。

これは計画変更であり失敗ではない。

同じ TaskOccurrence の `scheduledStart / scheduledEnd` を更新する。

### 予定開始後に変更

例: 10時を過ぎてもできず、12時に「18時へ移そう」と決めた。

この場合、10時の計画はすでに失敗している。

```text
旧 TaskOccurrence
10:00 → missed

新 TaskOccurrence
18:00 → pending
```

18時に実行できれば新 TaskOccurrence は `success` になる。

ユーザーが明示的に再スケジュールせず、単に18時に後から実行した場合は、旧 TaskOccurrence を `missed + actualExecutedAt 18:00` として扱う。

---

## 10. デイリーレビュー

Review は独立タブにしない。

Today の中で必要になった時だけ表示する。

### Review を出す条件

対象日は `scheduledStart` のローカル日付でまとめる。

次のどちらかを満たしたら Today 下部に `今日を振り返る` を表示する。

1. その日の予定 Task がすべて `success / missed / cancelled` のいずれかに確定した
2. その日の最後の Task の `scheduledEnd` を過ぎ、未確定 Task が残っている

これにより固定の「22時レビュー」を持たず、その人の生活時間に自然に追従する。

開始が23時、終了が翌1時の Task は、開始日の Review 対象として扱い、終了後に Review を出せる。

### Review で行うこと

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

Review は判定補助の UI であり、集計値を大量に別保存しない。

---

## 11. Insights

### 11.1 Insights 1ページ目

情報を増やしすぎない。

表示するのは 2 項目だけ。

```text
Insights

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

Task をタップすると、その Task の詳細を見る。

```text
英語学習

成功しやすい曜日
土 82%
日 74%
...

成功しやすい時間帯
午前 82%
昼 58%
夜 33%

おすすめ
土曜 10:00 が続けやすそうです
[この時間で予定する]
```

### 11.3 2種類の分析

#### 予定成功率

「予定した枠が機能したか」を見る。

```text
予定成功率 = success / (success + missed)
```

`cancelled / pending / 予定なし実行` は除外する。

今週の成功率はこの指標を使う。

#### 時間帯の適性

Task ごとの曜日 / 時間帯を見る時は、次の観測を利用する。

- 予定どおりできた → その時間帯に成功 1
- 予定に失敗した → 予定時間帯に失敗 1
- 後で実行した → 実際の実行時間帯に成功 1
- 予定なしで実行した → 実際の実行時間帯に成功 1

例:

```text
予定 10:00 → missed
実行 18:00 → success observation
```

これにより「10時は失敗しやすいが18時には実際に行動できている」という情報を残せる。

同じ時間帯内で予定どおり実行した場合は成功を二重カウントしない。

---

## 12. SuggestionEngine v0.1

高度な最適化は行わない。

候補を出す最低条件の例:

1. 同一 Task に一定数の履歴がある
2. 現在の曜日 / 時間帯に失敗傾向がある
3. 別の曜日 / 時間帯に成功の観測が十分ある
4. Calendar 上で候補時間が空いている
5. 改善幅が明確

初期案では同条件 3 件以上を目安にする。

```text
現在
火曜 22:00
成功率 25%

候補
土曜 10:00
成功率 75%

→ +50pt
```

提案には必ず理由を表示する。

ユーザーが承認した場合のみ予定変更を行う。

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

初回に `calendarIdentifier` を保存する。

Task / Event を Calendar に書き込む直前に利用可能か確認する。

```text
選択済みカレンダー
↓
まだ EventKit に存在する？
↓
YES → 使用

NO
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

Pocket 由来 Task の Calendar ミラーを外部 Calendar アプリから編集した場合の完全同期は MVP では扱わない。

MVP では Pocket Task を編集する時は Pocket を正とし、その変更を Calendar ミラーへ反映する。

通常 Event は Calendar が正本なので、EventKit から読んだ最新状態を表示する。

---

## 14. データモデル v0.1

モデル数を増やしすぎず、`Task + TaskOccurrence` を中心にする。

### Task

```text
id
title
category?             // 任意
estimatedDuration?    // 任意
createdAt
archivedAt?
```

優先度は持たない。

### TaskOccurrence

1 回の計画 / 実行を表す。

```text
id
taskID

scheduledStart?
scheduledEnd?

planResult?           // pending / success / missed / cancelled
actualExecutedAt?

calendarEventIdentifier?
calendarIdentifier?

createdAt
```

ルール:

- `scheduledStart != nil && planResult == pending` → 予定済み・未確定
- `planResult == success` → 予定した枠で実行できた
- `planResult == missed` → 予定した枠では実行できなかった
- `actualExecutedAt != nil` → 実際にはその時刻に Task を実行できた
- `scheduledStart == nil && actualExecutedAt != nil` → 予定なしの自発実行
- `cancelled` は成功率対象外

### ReviewRecord

Review を済ませた日の最小状態だけ保持する。

```text
id
dateKey
reviewedAt
```

予定数・完了数などは TaskOccurrence から計算し、重複保存しない。

### App Settings

最低限:

```text
defaultCalendarIdentifier
notificationDefaults
```

UserDefaults / AppStorage 等で十分なものは SwiftData モデルを増やさない。

---

## 15. 実装境界

大規模な Clean Architecture は採用しない。

ただし Apple API を View から直接ばら撒かない。

```text
SwiftUI
   │
   ├─ TaskRepository
   │      └─ SwiftData
   │
   ├─ CalendarService
   │      └─ EventKitAdapter
   │
   ├─ NotificationService
   │      └─ UserNotifications
   │
   ├─ InsightsEngine
   │      └─ Foundation のみで計算可能
   │
   └─ SuggestionEngine
          └─ Foundation のみで計算可能
```

### TaskRepository

- Task / TaskOccurrence の保存・取得
- SwiftData 固有処理を UI から隠す

### CalendarService

- Calendar 一覧
- Calendar 利用可否
- Event 読み込み
- Event 作成 / 更新 / 削除

MVP 実装は EventKitAdapter だけ。

### NotificationService

- Task 通知の登録 / 更新 / 削除

### InsightsEngine

- 予定成功率
- 曜日 / 時間帯観測
- Task 別集計

EventKit / SwiftUI を知らない純粋ロジックにする。

### SuggestionEngine

- 履歴と空き時間を入力に候補を返す
- 自分で Calendar を変更しない

---

## 16. 画面構成 v0.1

### Today

- 今日の時間軸
- Task
- Calendar Event
- Task 完了操作
- 未スケジュール Task
- 条件成立後に `今日を振り返る`

### Tasks

- Task 一覧
- 未スケジュール
- 今後の Task
- Task 追加 / 編集

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

Review は独立タブにしない。

UI 基準は `docs/ui/` を参照する。

---

## 17. 主要エラーケース

MVP で最低限扱う。

### Calendar 権限なし

- Task 自体は作成可能
- Calendar 反映が必要な時に権限案内

### 既定 Calendar が消えた

- Task は保持
- Calendar 再選択を要求

### Calendar Event 作成失敗

- SwiftData の Task を消さない
- ユーザーへ再試行可能な状態を示す

### 通知権限なし

- 通知なしで利用継続

### Task の Calendar ミラーが見つからない

- Task は Pocket が正本なので保持
- 必要なら次回編集時に Calendar ミラーを再作成可能にする

---

## 18. MVP テストで特に守るケース

### InsightsEngine

1. 10時予定 → 10時に成功
2. 10時予定 → 未実行
3. 10時予定 → 18時に後から実行
4. 予定なし → 18時に自発実行
5. cancelled は成功率から除外
6. 同じ時間帯で予定成功した場合に成功を二重計上しない

### 予定変更

1. 開始前変更は失敗にしない
2. 開始後変更は旧予定を missed、新予定を新規 TaskOccurrence とする

### Calendar

1. 選択済み Calendar が存在する
2. 選択済み Calendar が削除済み
3. Pocket Task の Calendar ミラーを Today で二重表示しない

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

MVP が成立した後に検討する。

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
