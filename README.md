# Javaリスタート（iOS / SwiftUI）

Java を体系的に学び直すための iOS アプリです。

- **参考書**：4部17章（基礎文法 → オブジェクト指向 → 標準API → モダンJava）。各章に本文・コード例・要点・落とし穴。読み終えたら「読了にする」
- **ノート**：質問して解説してもらった内容を「聞く用の台本」にした学習ノート。iPhoneの日本語音声で読み上げる（連続再生・段落スキップ・速さ 0.8〜1.5倍・バックグラウンド再生・ロック画面操作）。最後まで聞いたノートは進捗に記録
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
  NotesView.swift        学習ノート（一覧・台本・ミニプレイヤー）
  SpeechPlayer.swift     読み上げ（AVSpeechSynthesizer）と台本の読み込み
  Info.plist             バックグラウンド再生の設定（自動生成分と合成される）
  Components.swift       コード表示（ハイライト）・表・進捗リングなど
  Resources/
    parts.json  book.json  quiz.json  steps.json  notes.json
```

## 内容を増やすには

- 章を追加・修正：`Resources/book.json`。本文のブロックは `p`（段落）、`list`、`table`、`code` の4種類。段落内は `` `コード` `` と `**太字**` が使えます
- 問題を追加：`Resources/quiz.json`。`chapter` に章番号を入れると、その章の確認問題になります
- 学習ノートを追加：`Resources/notes.json` の `notes` の末尾に追記。台本（`script`）は1段落1要素で、コードは言葉で説明する。英単語は `readings` に読み（カタカナ）を登録すると、その読みで発音される
- 読み上げの声は端末の日本語音声で最も品質の高いものを使う。設定 → アクセシビリティ → 読み上げコンテンツ → 声 → 日本語 で「拡張」の声をダウンロードすると自然になる
- 進捗は端末内にだけ保存されます（アプリを削除すると消えます）
