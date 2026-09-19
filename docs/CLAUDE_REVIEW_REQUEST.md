# Claude Architecture Review Request

> Status: Completed on 2026-09-19. Keep this document as the review checklist for future major design changes.

実装前に TechAssistantPocket の MVP 設計をレビューするための依頼書。

## 目的

現在の設計が、以下を同時に満たしているか確認する。

1. MVP が膨らみすぎていない
2. 後から拡張できる最低限の境界がある
3. データモデルがコア体験を正しく表現できる
4. EventKit / SwiftData / UserNotifications の責務が混ざっていない
5. 初期実装で詰まりそうな穴がない

## 必ず読むもの

- `README.md`
- `docs/DESIGN.md`
- `docs/DEVELOPMENT_KNOWLEDGE.md`
- `docs/ui/README.md`
- `CLAUDE.md`

必要なら `Hanio-stack/dev-knowledge` の関連項目も参照する。

## 特に確認してほしいケース

### 1. 予定失敗 + 後から成功

```text
Task: 英語学習
予定: 10:00
実行: 18:00
```

次の両方を失わず保存・分析できるか。

- 10時の計画は失敗
- 18時には実際に英語学習を実行できた

現設計は 1 個の `TaskOccurrence` に `planResult = missed` と `actualExecutedAt = 18:00` を持たせる。

この方法に致命的な矛盾がないか確認する。

### 2. 予定変更

- 開始前の変更は失敗にしない
- 開始後の変更は旧予定を `missed`、新予定を別 TaskOccurrence にする

このルールが分析を壊さないか確認する。

### 3. 通常 Event と Task

- Task の正本 = SwiftData
- 通常 Event の正本 = EventKit
- Task の Calendar Event はミラー

Today の二重表示回避や編集責務に問題がないか確認する。

### 4. Calendar 消失

保存済み `calendarIdentifier` が iPhone から消えた場合:

- Task 自体は失わない
- Calendar 再選択を促す

これで十分か確認する。

### 5. Review

Review タブは持たない。

その日の Task がすべて確定した、または最後の `scheduledEnd` を過ぎた時だけ Today に Review 導線を出す。

固定の就寝時刻設定を持たず、Task の並びから生活時間に追従する設計に穴がないか確認する。

### 6. Insights

1ページ目は以下だけ。

- 今週の予定成功率
- Task 別一覧

Task 詳細で曜日 / 時間帯の傾向を見る。

予定成功率と実際の実行時刻の観測を混同していないか確認する。

## レビューの制約

- **実装はしない**
- MVP に新機能を足すことを目的にしない
- 一般論だけで大規模アーキテクチャを提案しない
- 新しい依存やバックエンドを前提にしない
- 問題がある場合は「最小の修正」で解決案を出す
- 将来あると便利なものは `Later` として分離する

## 出力形式

以下の形式で回答する。

### Verdict

- このまま MVP 実装開始可能 / 修正してから開始 / 設計見直しが必要
- 理由を 3〜5 行

### Blockers

実装開始前に直す必要があるものだけ。

各項目:

```text
問題:
なぜ問題か:
最小修正:
```

なければ `なし`。

### Important but not blocking

MVP 中に気をつけるもの。

### Later

MVP 後で十分なもの。

### Overengineering check

現設計の中で MVP に不要な抽象化・モデル・画面・状態があれば指摘する。

### Missing tests

実装前にテスト観点として追加すべきケースだけを列挙する。

## 最後の質問

レビューの最後に、次へ答える。

> 「この設計を SwiftUI + SwiftData + EventKit + UserNotifications だけで v0.1 として作り始めてもよいか？」

Yes / No と短い理由を出す。
