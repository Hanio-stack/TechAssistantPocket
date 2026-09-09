# Development Knowledge Policy

TechAssistantPocket の開発では、共有ノウハウリポジトリ [`Hanio-stack/dev-knowledge`](https://github.com/Hanio-stack/dev-knowledge) を参照する。

目的は「知識を大量に持ち込むこと」ではなく、今回の作業に実際に役立つ、検証済みの知見だけを再利用し、TechAssistantPocket で得られた再利用可能な知見を必要に応じて共有資産へ戻すこと。

## 優先順位

1. TechAssistantPocket 固有の仕様・設計判断
2. TechAssistantPocket の現在の実装とテスト
3. `dev-knowledge` の Rules / Patterns / Failures / Knowledge
4. 一般的な慣習

共有ノウハウとプロジェクト固有の判断が衝突した場合は、TechAssistantPocket 側を優先する。

## 作業前

実装や大きな設計作業を始める前に以下を行う。

1. `README.md` と `docs/DESIGN.md`、関連 Issue を確認する。
2. 現在のコード、テスト、Git 状態を確認する。
3. 作業内容に関係するカテゴリだけ `dev-knowledge` を検索する。
4. 適用する知見と、今回は適用しない知見を区別する。
5. 高コストで戻しにくい設計変更・大規模依存追加は Human Gate として人間の判断を挟む。

## 現時点で特に関連する共有知識

### AI 開発ルール

`dev-knowledge/rules/ai-development.md`

- 既存システムを共有ルールに合わせるためだけに書き直さない。
- 確認済みの事実と仮説を分ける。
- 大きな依存・アーキテクチャ変更は Human Gate を置く。
- 一度だけ起きた事象をすぐ共有ルールへ一般化しない。

Claude Code を使う場合もこの方針を適用する。

### 開発原則

`dev-knowledge/rules/development-principles.md`

- 変更前に現状を読む。
- 不確実なときは、小さく、テストしやすく、戻しやすい変更を優先する。
- 結果だけでなく「なぜその判断をしたか」を残す。
- 重複ノウハウを増やさない。

### プロジェクト開始チェック

`dev-knowledge/templates/project-start.md`

実装開始時に、プロジェクト固有ルール・関連共有知識・既存アーキテクチャを確認してから着手する。

### iPhone 日本語 UI

`dev-knowledge/patterns/mobile-japanese-layout-wrapping.md`

- 狭い画面で日本語見出しと補足文を無理に横並びにしない。
- 文字サイズを縮めるより、必要なら縦積みに逃がす。
- 実機スクリーンショットで確認する。

TechAssistantPocket は iPhone 専用アプリなので、UI 実装時に優先的に参照する。

### CI と外部依存の分離

`dev-knowledge/patterns/deterministic-ci-and-live-source-smoke.md`

将来、外部サービスや実カレンダー状態を使う検証を CI に追加する場合、通常の unit test と live smoke を分離する。

コード自身の正しさと、外部サービスの一時的な不調を同じ FAIL として扱わない。

## TechAssistantPocket から共有資産へ戻す流れ

意味のある作業区切りごとに Knowledge Review を行う。

候補ごとに以下を確認する。

1. TechAssistantPocket 固有の話ではないか。
2. `dev-knowledge` に既存の同等知識がないか。
3. 実装・テスト・実機確認などで十分に検証されたか。
4. Knowledge / Rule / Pattern / Failure のどれか。
5. 一度きりの workaround ではなく、他プロジェクトでも価値があるか。

条件を満たす場合のみ `dev-knowledge` への追加・既存項目の拡張を検討する。

## ライブラリ化の方針

コードの共通化は早すぎる抽象化を避ける。

まず TechAssistantPocket 内で実装・検証し、責務と API が安定してから共有化を判断する。

現時点の候補:

- EventKit を包む Calendar Adapter
- Local Notification の Scheduler
- 時間帯 / 曜日別の成功率集計ロジック
- スケジュール提案のルールエンジン
- 日付・時間帯テスト用の Test Helpers

これらは「候補」であり、実装前に共有ライブラリ化しない。プロジェクト内で十分に安定したものだけを切り出す。

## Claude Code 開発時の基本ループ

```text
Project docs / Issue を読む
        ↓
関連する dev-knowledge のみ確認
        ↓
小さい実装単位を決める
        ↓
実装
        ↓
Build / Test
        ↓
失敗なら原因確認 → 修正
        ↓
成功
        ↓
変更内容と判断理由を記録
        ↓
Knowledge Review
```

Claude が勝手に新しい共有ルールやライブラリを増やすのではなく、検証済みで再利用価値があるものだけを候補として扱う。
