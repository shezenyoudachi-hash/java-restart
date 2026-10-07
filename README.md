# Javaリスタート（iOS / SwiftUI）

Java を体系的に学び直すための iOS アプリです。

- **参考書**：4部17章（基礎文法 → オブジェクト指向 → 標準API → モダンJava）。各章に本文・コード例・要点・落とし穴。読み終えたら「読了にする」
- **ドリル**：33問。カテゴリ別・章ごとの確認問題・間違えた問題だけ、で出題。解説から該当章へ戻れる
- **進捗**：読了率リング、部ごとの読了バー、カテゴリ別の正解数、12週間の学習カレンダー、連続学習日数
- **作って学ぶ**：原料受入・試験管理（ミニ版）を8ステップで作る課題とチェックリスト

## 動かし方

1. `JavaRestart.xcodeproj` を Xcode 16 以降で開く
2. ターゲット JavaRestart → Signing & Capabilities → Team に自分の Apple ID のチームを選ぶ
   （必要なら Bundle Identifier の `com.example.JavaRestart` を自分用に変更）
3. シミュレータか実機を選んで実行（iOS 17 以降）

ファイルは `JavaRestart/` フォルダ同期型のグループで管理しているので、フォルダに Swift ファイルや JSON を追加すると自動でプロジェクトに含まれます。

## 構成

```
JavaRestart/
  JavaRestartApp.swift   アプリ本体とタブ
  Models.swift           データ型と JSON の読み込み
  ProgressStore.swift    進捗の保存（UserDefaults）と集計
  BookView.swift         参考書の目次と章の本文
  DrillView.swift        ドリル
  StatsView.swift        進捗画面・学習カレンダー
  BuildView.swift        作って学ぶ
  Components.swift       コード表示（ハイライト）・表・進捗リングなど
  Resources/
    parts.json  book.json  quiz.json  steps.json
```

## 内容を増やすには

- 章を追加・修正：`Resources/book.json`。本文のブロックは `p`（段落）、`list`、`table`、`code` の4種類。段落内は `` `コード` `` と `**太字**` が使えます
- 問題を追加：`Resources/quiz.json`。`chapter` に章番号を入れると、その章の確認問題になります
- 進捗は端末内にだけ保存されます（アプリを削除すると消えます）
