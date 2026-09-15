# Claude Code Instructions — TechAssistantPocket

このリポジトリでは **MVP を小さく保ちながら、後から交換可能な境界だけを用意する**。

## 最初に読む

作業前に必ず次の順で確認する。

1. `README.md`
2. `docs/DESIGN.md`
3. `docs/DEVELOPMENT_KNOWLEDGE.md`
4. UI 作業なら `docs/ui/README.md` と画像
5. 必要な場合だけ `Hanio-stack/dev-knowledge` の関連項目

プロジェクト固有仕様を共有ノウハウより優先する。

## MVP ガードレール

MVP では以下を追加しない。

- OpenAI / Anthropic 等の LLM API
- 自前バックエンド
- Google Calendar API 直接連携
- 複雑な自動スケジューリング
- 独立 Review タブ
- Task 優先度
- 不要な外部ライブラリ
- 将来用途だけを理由にした抽象化

新機能が必要に見えても、まず既存 MVP のコアループで解決できないか確認する。

## アーキテクチャ方針

大規模な Clean Architecture は作らない。

ただし次の境界は守る。

```text
SwiftUI
├─ TaskRepository -> SwiftData
├─ CalendarService -> EventKitAdapter
├─ NotificationService -> UserNotifications
├─ InsightsEngine -> 純粋ロジック
└─ SuggestionEngine -> 純粋ロジック
```

- `InsightsEngine` と `SuggestionEngine` は EventKit / SwiftUI に依存させない
- Calendar の実装詳細を View に直接広げない
- Task の正本は SwiftData
- 通常 Event の正本は EventKit

## 実装ループ

実装を依頼された場合:

1. Issue / 仕様 / UI を読む
2. 最小変更を計画
3. 実装
4. Build
5. Unit Test
6. 失敗したら原因を確認して修正
7. UI 変更なら Simulator / 実機で確認
8. 仕様と差分を再確認
9. 完了条件を満たすまで繰り返す

テストを通すためだけに仕様を変更しない。

## Human Gate

次の場合は勝手に進めず確認する。

- 新しい外部依存の追加
- データモデルの大幅変更
- EventKit 以外の Calendar 実装追加
- CloudKit / サーバー導入
- 既存仕様と矛盾する変更
- 戻しにくいマイグレーション

## 現在のレビュー

実装開始前の設計レビューを行う場合は `docs/CLAUDE_REVIEW_REQUEST.md` に従う。
