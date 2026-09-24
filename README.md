# TechAssistantPocket

テック秘書のコンセプトを引き継ぎつつ、機能・運用コスト・開発規模を絞った iOS 向けの「行動改善型スケジューラ」。

## コンセプト

**予定を管理するだけではなく、実行結果から「予定の立て方」を改善していく。**

一般的な Todo / Calendar アプリが「登録 → 通知 → 完了」で終わるのに対し、TechAssistantPocket は以下のループを中心にする。

> Plan → Do → Review → Improve → Plan

ユーザーが「いつ予定したか」と「実際にいつできたか」を端末内で蓄積し、曜日・時間帯ごとの傾向から次のスケジュールを提案する。

## 設計思想

- **運用コスト 0 を最優先する**
  - OpenAI API / LLM API を使用しない
  - 自前サーバーを持たない
  - MVP では Google Calendar API を直接使用しない
- **Local First**
  - Task / 実行履歴 / Review 状態は原則 iPhone 内に保存する
  - 将来必要になれば CloudKit 同期を追加する
- **Apple 標準機能を最大限使う**
  - SwiftUI: UI
  - SwiftData: Pocket 独自データ
  - EventKit: iPhone カレンダー連携
  - UserNotifications: ローカル通知
- **機能数では競争しない**
  - Todoist / TickTick / Google Calendar の代替を目指さない
  - 「予定の立て方が上手くなっていく」という一点をコア価値にする
- **自動化しても勝手に予定を変えない**
  - 分析 → 提案 → ユーザー承認 → 変更、の順を守る
- **MVP を小さく保ちつつ交換可能な境界を作る**
  - SwiftData / EventKit / UserNotifications を View から直接ばら撒かず、薄い Repository / Service の後ろに置く
  - 将来 Google Calendar API や CloudKit に置き換える場合も UI / 分析ロジックを作り直さない

## ユーザーが扱うものは 2 種類だけ

### Task

「自分が達成したいこと」。

例: 英語学習、ジム、BK 制作、読書。

- 完了 / 未完了を記録する
- Insights / Review の対象
- スケジュール済みなら EventKit にカレンダーイベントを作る
- **正本は Pocket (SwiftData)**

### Event

「その時間にあるだけの予定」。

例: 映画、食事、美容院、会議。

- 完了判定をしない
- 成功率に含めない
- 空き時間判定と Today 表示には使う
- Pocket から追加する場合も EventKit に直接保存する
- **正本は Calendar (EventKit)**

`+` を押した時だけ `Task / 予定` に分岐し、通常利用の画面数は増やさない。

## MVP v0.1

1. Task の追加 / 編集 / 削除
2. Task に日時・所要時間・通知を設定（日時なしも可）
3. 通常の Calendar Event を追加
4. Today に Task と Calendar Event を同じ時間軸で表示
5. Task の完了 / 未完了と、実際に実行した時刻を記録
6. EventKit で既存カレンダーを参照し、スケジュール済み Task を指定カレンダーへ反映
7. 選択済みカレンダーが消えた場合に再選択を促す
8. ローカル通知
9. Today から行うデイリーレビュー（独立 Review タブは持たない）
10. 今週の予定成功率と Task 別 Insights
11. Task 詳細で曜日・時間帯の傾向を表示
12. 履歴と空き時間から簡単なスケジュール変更を提案

**Task の優先度は MVP では持たない。** 利用先がない入力項目を増やさないため、必要になった段階で追加する。

## MVP の完成条件

**1週間使うと、自分が Task を実行しやすい曜日・時間帯が見え、次の予定改善を提案してくれること。**

チャット AI、自然言語入力、複雑な全自動スケジューリング、Google Calendar API 直接連携、チーム共有は MVP に含めない。

## 技術構成

```text
SwiftUI
   │
   ├─ TaskRepository ───────── SwiftData
   │
   ├─ CalendarService ──────── EventKit
   │      └─ EventKitAdapter (MVP)
   │
   ├─ NotificationService ──── UserNotifications
   │
   ├─ InsightsEngine
   │      └─ 純粋な履歴分析
   │
   └─ SuggestionEngine
          └─ 説明可能なルールベース提案
```

MVP では実装を過度に抽象化せず、外部依存との境界だけ薄く分ける。

## Google Calendar

iPhone に Google アカウントのカレンダーが追加されていれば、EventKit から保存先として選択できる。

```text
Pocket
  ↓
EventKit
  ↓
iOS の Google カレンダー
  ↓
Google Calendar と同期
```

Google OAuth / Calendar API は MVP では持たない。

## 画面構成

- **Today**: 現在 Task のスキップ / 完了、次の Task / Event、日付切り替え、折りたたみ履歴・未確定、条件を満たしたら振り返り
- **Tasks**: Task 一覧、未スケジュール、今後の Task、追加 / 編集
- **Insights**: 1ページ目は「今週の成功率」と「Task 別」のみ
  - Task をタップすると曜日・時間帯の詳細と提案を表示
- **Settings**: 既定カレンダー、通知など。独立タブにするかは実装時に最小導線を優先して判断

Review は独立タブにしない。

## ドキュメント

- [Claude Code 引き継ぎ](docs/CLAUDE_HANDOFF.md)
- [Home v2 修正第二弾の確認](docs/HOME_V2_VALIDATION.md)
- [詳細設計・ユーザーフロー](docs/DESIGN.md)
- [開発ノウハウ連携](docs/DEVELOPMENT_KNOWLEDGE.md)
- [UI Mockups](docs/ui/README.md)
- [Claude Architecture Review Request](docs/CLAUDE_REVIEW_REQUEST.md)
- [作業ログ](WORKLOG.md)

今後、仕様変更や設計判断は GitHub を正として追記する。実装タスクは GitHub Issues、実際に行った作業や判断は `WORKLOG.md` に残す。
