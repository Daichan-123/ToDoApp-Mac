# Random TODO (macOS)

## 概要
ランダムにタスクを選出して集中作業を支援する macOS アプリ。
作業時間の計測、履歴保存、ストリーク管理を行う。

---

## 主な機能

- タスク追加
- ランダム選出
- 完了時の作業時間計測（非表示タイマー）
- 達成率ゲージ
- 今日の作業時間集計
- 日別履歴保存
- ストリーク（連続達成日数）
- UserDefaults による永続保存
- アプリ再起動時の状態復元

---

## 画面構成

### 1. Home
- タスク追加
- ランダム選出
- 完了ボタン
- 今日の進捗表示
- タスクリスト

### 2. History
- 日別履歴一覧
- 完了タスク
- 作業時間

### 3. Streak
- 現在ストリーク
- 最長ストリーク
- 最終達成日
- 直近7日達成状況

---

## 技術構成

- SwiftUI
- macOS App
- MVVM風構成
- ObservableObject による状態管理
- UserDefaults 保存

---

## ファイル構成
RandomTodo
├─ ContentView.swift
├─ TaskStore.swift
├─ Models.swift
├─ HomeView.swift
├─ HistoryView.swift
├─ StreakView.swift
---

## データモデル

### TaskItem
- id
- title
- isDone
- elapsedSeconds

### DailyHistory
- dateKey
- completedCount
- totalSeconds
- completedTasks

### CompletedTaskRecord
- title
- elapsedSeconds

---

## 今後追加予定

- [ ] UI改善
- [ ] タスク編集機能
- [ ] 通知機能
- [ ] Dockバッジ
- [ ] 設定画面
- [ ] Appアイコン
- [ ] ダークモード最適化
- [ ] テスト追加
- [ ] 配布対応

---

## テスト対象

- タスク追加
- ランダム選出
- 完了処理
- 履歴保存
- ストリーク計算

---

## 公開予定

配布方法:
- App Store (検討中)
- 直接配布 (Developer ID)

---

## 開発メモ

- ストップウォッチはUI非表示
- 日付単位で履歴管理
- 完了時に自動で次タスク選出
- 再起動時に実行中タスク復元
