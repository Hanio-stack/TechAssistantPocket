# TechAssistantPocket

テック秘書のコンセプトを引き継ぎつつ、機能・運用コスト・開発規模を絞った iOS 向けの「行動改善型スケジューラ」。

## コンセプト

**予定を管理するだけではなく、実行結果から「予定の立て方」を改善していく。**

一般的な Todo / Calendar アプリが「登録 → 通知 → 完了」で終わるのに対し、TechAssistantPocket は以下のループを中心にする。

> Plan → Do → Review → Improve → Plan

ユーザーが実際にタスクを完了できた曜日・時間帯・タスク種別などを端末内で蓄積し、成功率をもとに次のスケジュールを提案する。

## 設計思想

- **運用コスト 0 を最優先する**
  - OpenAI API を使用しない
  - 自前サーバーを持たない
  - 初期版では Google Calendar API を直接使用しない
- **Local First**
  - タスク、実行履歴、レビューは原則 iPhone 内に保存する
  - 将来必要になれば iCloud / CloudKit 同期を追加する
- **Apple 標準機能を最大限使う**
  - SwiftUI: UI
  - SwiftData: ローカルデータ
  - EventKit: iPhone カレンダー連携
  - UserNotifications: ローカル通知
- **Google Calendar は EventKit 経由で扱う**
  - iPhone に Google アカウントのカレンダーが追加されていれば、EventKit からそのカレンダーを保存先として選べる
  - TechAssistantPocket から登録した予定を Google Calendar に同期可能
  - Google OAuth / Calendar API は MVP では持たない
- **AI に見える体験を、まずはルールベースで作る**
  - 曜日別成功率
  - 時間帯別成功率
  - タスク別成功率
  - 過去の実績から「この時間に移した方が成功しやすい」を提案する
- **機能数では競争しない**
  - Todoist / TickTick / Google Calendar の代替を目指さない
  - 「予定の立て方が上手くなっていく」という一点をコア価値にする

## MVP v0.1

1. タスクを自由に追加・編集・削除
2. タスクに日時・所要時間・優先度を設定
3. 今日のタスクを時系列表示
4. 完了 / 未完了を記録
5. EventKit で iPhone カレンダーの予定を参照
6. 指定したカレンダーへスケジュール済みタスクを追加
7. ローカル通知
8. デイリーレビュー
9. 曜日・時間帯などの成功率を集計
10. 成功率を使った簡単なスケジュール変更提案

## MVP の完成条件

**1週間使うと、自分がタスクを成功させやすい曜日・時間帯が見え、翌週の予定改善を提案してくれること。**

チャット AI、自然言語入力、複雑な自動スケジューリング、Google Calendar API 直接連携は MVP に含めない。

## 技術構成

```text
TechAssistantPocket (iOS)
├─ Swift / SwiftUI
├─ SwiftData
│  └─ Task / TaskHistory / DailyReview
├─ EventKit
│  ├─ 既存カレンダー予定の参照
│  └─ 選択したカレンダーへの予定作成
├─ UserNotifications
│  └─ タスク通知 / デイリーレビュー通知
└─ CloudKit（将来・任意）
   └─ 複数 Apple 端末間同期
```

## ドキュメント

- [設計・ユーザーフロー](docs/DESIGN.md)
- [作業ログ](WORKLOG.md)

今後、仕様変更や設計判断は GitHub を正として追記していく。実装タスクは GitHub Issues、実際に行った作業や判断は `WORKLOG.md` に残す想定。
