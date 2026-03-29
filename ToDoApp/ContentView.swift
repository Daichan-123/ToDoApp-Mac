import SwiftUI
import Combine

// MARK: - タスク1件分のモデル
// title: タスク名
// isDone: 完了済みかどうか
// elapsedSeconds: 完了までにかかった秒数
struct TaskItem: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var isDone: Bool
    var elapsedSeconds: Int

    init(id: UUID = UUID(), title: String, isDone: Bool = false, elapsedSeconds: Int = 0) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.elapsedSeconds = elapsedSeconds
    }
}

// MARK: - 履歴内の完了タスク1件
struct CompletedTaskRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    let elapsedSeconds: Int

    init(id: UUID = UUID(), title: String, elapsedSeconds: Int) {
        self.id = id
        self.title = title
        self.elapsedSeconds = elapsedSeconds
    }
}

// MARK: - 1日単位の履歴
// dateKey: yyyy-MM-dd 形式の日付キー
// completedCount: その日に完了した件数
// totalSeconds: その日の合計作業時間
// completedTasks: 完了したタスクの一覧
struct DailyHistory: Identifiable, Codable, Equatable {
    let id: UUID
    let dateKey: String
    var completedCount: Int
    var totalSeconds: Int
    var completedTasks: [CompletedTaskRecord]

    init(
        id: UUID = UUID(),
        dateKey: String,
        completedCount: Int = 0,
        totalSeconds: Int = 0,
        completedTasks: [CompletedTaskRecord] = []
    ) {
        self.id = id
        self.dateKey = dateKey
        self.completedCount = completedCount
        self.totalSeconds = totalSeconds
        self.completedTasks = completedTasks
    }
}

// MARK: - 実行中タスクの復元用セッション情報
// taskID: 実行中のタスクID
// startTime: 開始時刻
// dateKey: そのセッションが属する日付
struct ActiveSession: Codable, Equatable {
    var taskID: UUID
    var startTime: Date
    var dateKey: String
}

// MARK: - アプリ全体の状態管理
// タスク、履歴、実行中タスク、保存/復元などのロジックをまとめる
final class TaskStore: ObservableObject {
    // UserDefaults の保存キー
    private let tasksStorageKey = "randomTodo.tasks"
    private let historyStorageKey = "randomTodo.history"
    private let activeSessionStorageKey = "randomTodo.activeSession"
    private let lastActiveDateKeyStorageKey = "randomTodo.lastActiveDateKey"

    // 入力中のテキスト
    @Published var inputText: String = ""

    // 今日のタスク一覧
    @Published var tasks: [TaskItem] = []

    // 日別履歴
    @Published var history: [DailyHistory] = []

    // 現在実行中のタスクID
    @Published var currentTaskID: UUID? = nil

    // 現在実行中タスクの開始時刻
    @Published var startTime: Date? = nil

    // 最終確認した日付キー
    @Published var lastCheckedDateKey: String = ""

    init() {
        self.tasks = Self.loadTasks()
        self.history = Self.loadHistory()
        rolloverIfNeeded()
        restoreActiveSession()
    }

    // MARK: - 計算プロパティ

    // 達成率（0.0〜1.0）
    var completionRate: Double {
        guard !tasks.isEmpty else { return 0 }
        let doneCount = tasks.filter { $0.isDone }.count
        return Double(doneCount) / Double(tasks.count)
    }

    // 現在実行中のタスク本体
    var currentTask: TaskItem? {
        guard let currentTaskID else { return nil }
        return tasks.first(where: { $0.id == currentTaskID })
    }

    // 未完了タスク一覧
    var remainingTasks: [TaskItem] {
        tasks.filter { !$0.isDone }
    }

    // 今日の日付キー
    var todayKeyValue: String {
        todayKey()
    }

    // 今日の合計作業時間
    var todayTotalSeconds: Int {
        history.first(where: { $0.dateKey == todayKey() })?.totalSeconds ?? 0
    }

    // 今日の完了件数
    var todayCompletedCount: Int {
        history.first(where: { $0.dateKey == todayKey() })?.completedCount ?? 0
    }

    // 新しい日付順で履歴を並べる
    var sortedHistory: [DailyHistory] {
        history.sorted { $0.dateKey > $1.dateKey }
    }

    // 現在の連続達成日数
    var streakCount: Int {
        let activeDays = Set(
            history
                .filter { $0.completedCount > 0 }
                .map { $0.dateKey }
        )

        guard !activeDays.isEmpty else { return 0 }

        let calendar = Calendar(identifier: .gregorian)
        let formatter = Self.dayFormatter
        var currentDate = calendar.startOfDay(for: Date())
        var count = 0

        while true {
            let key = formatter.string(from: currentDate)
            if activeDays.contains(key) {
                count += 1
                guard let previous = calendar.date(byAdding: .day, value: -1, to: currentDate) else { break }
                currentDate = previous
            } else {
                break
            }
        }

        return count
    }

    // 最長連続達成日数
    var longestStreak: Int {
        let formatter = Self.dayFormatter
        let calendar = Calendar(identifier: .gregorian)

        let dates = history
            .filter { $0.completedCount > 0 }
            .compactMap { formatter.date(from: $0.dateKey) }
            .sorted()

        guard !dates.isEmpty else { return 0 }

        var longest = 1
        var current = 1

        for index in 1..<dates.count {
            let prev = calendar.startOfDay(for: dates[index - 1])
            let currentDate = calendar.startOfDay(for: dates[index])

            let diff = calendar.dateComponents([.day], from: prev, to: currentDate).day ?? 0

            if diff == 1 {
                current += 1
                longest = max(longest, current)
            } else if diff > 1 {
                current = 1
            }
        }

        return longest
    }

    // 最後に達成した日
    var lastCompletedDateText: String {
        sortedHistory.first(where: { $0.completedCount > 0 })?.dateKey ?? "まだなし"
    }

    // 直近7日分の達成状況
    var last7DaysStatus: [(dateKey: String, didComplete: Bool)] {
        let calendar = Calendar(identifier: .gregorian)
        let formatter = Self.dayFormatter
        let activeDays = Set(
            history
                .filter { $0.completedCount > 0 }
                .map { $0.dateKey }
        )

        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            let key = formatter.string(from: date)
            return (key, activeDays.contains(key))
        }
    }

    // MARK: - タスク操作

    // タスクを追加
    func addTask() {
        rolloverIfNeeded()

        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        tasks.append(TaskItem(title: trimmed))
        inputText = ""
        saveTasks()
    }

    // 未完了タスクからランダムに1件選んで実行開始
    func pickRandomTask() {
        rolloverIfNeeded()
        guard currentTaskID == nil else { return }

        let candidates = tasks.filter { !$0.isDone }
        guard let picked = candidates.randomElement() else { return }

        currentTaskID = picked.id
        startTime = Date()
        saveActiveSession()
    }

    // 実行中タスクを完了にし、履歴へ反映。次の未完了タスクがあれば自動選出
    func completeCurrentTask() {
        rolloverIfNeeded()
        guard let currentTaskID else { return }

        let elapsed = max(0, startTime.map { Int(Date().timeIntervalSince($0)) } ?? 0)

        if let index = tasks.firstIndex(where: { $0.id == currentTaskID }) {
            tasks[index].isDone = true
            tasks[index].elapsedSeconds = elapsed

            appendHistoryRecord(
                title: tasks[index].title,
                elapsedSeconds: elapsed
            )
        }

        startTime = nil
        self.currentTaskID = nil
        clearActiveSession()
        saveTasks()

        let nextCandidates = tasks.filter { !$0.isDone }
        if let nextTask = nextCandidates.randomElement() {
            self.currentTaskID = nextTask.id
            self.startTime = Date()
            saveActiveSession()
        }
    }

    // 同じ内容のタスクを新規追加する
    // 例: 「英語20分」をもう1回やりたい時に使う
    func repeatTask(_ task: TaskItem) {
        rolloverIfNeeded()

        let repeatedTask = TaskItem(title: task.title)
        tasks.append(repeatedTask)
        saveTasks()
    }

    // 未完了タスクだけまとめて削除
    func clearRemainingTasks() {
        rolloverIfNeeded()
        tasks.removeAll { !$0.isDone }

        if currentTaskID != nil {
            currentTaskID = nil
            startTime = nil
            clearActiveSession()
        }

        inputText = ""
        saveTasks()
    }

    // 履歴を全削除
    func clearHistory() {
        history.removeAll()
        saveHistory()
    }

    // タスクを削除
    func deleteTasks(at offsets: IndexSet) {
        let deletingIDs = offsets.map { tasks[$0].id }

        if let currentTaskID, deletingIDs.contains(currentTaskID) {
            self.currentTaskID = nil
            self.startTime = nil
            clearActiveSession()
        }

        tasks.remove(atOffsets: offsets)
        saveTasks()
    }

    // 秒数を見やすい文字列に整形
    func formattedTime(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60

        if hours > 0 {
            return "\(hours)時間\(minutes)分\(remainingSeconds)秒"
        } else if minutes > 0 {
            return "\(minutes)分\(remainingSeconds)秒"
        } else {
            return "\(remainingSeconds)秒"
        }
    }

    // MARK: - 履歴操作

    // 完了タスクを今日の履歴に追加
    private func appendHistoryRecord(title: String, elapsedSeconds: Int) {
        let key = todayKey()
        let record = CompletedTaskRecord(title: title, elapsedSeconds: elapsedSeconds)

        if let index = history.firstIndex(where: { $0.dateKey == key }) {
            history[index].completedCount += 1
            history[index].totalSeconds += elapsedSeconds
            history[index].completedTasks.append(record)
        } else {
            history.append(
                DailyHistory(
                    dateKey: key,
                    completedCount: 1,
                    totalSeconds: elapsedSeconds,
                    completedTasks: [record]
                )
            )
        }

        saveHistory()
    }

    // MARK: - 日付処理

    // 今日の日付キーを返す
    private func todayKey() -> String {
        Self.dayFormatter.string(from: Date())
    }

    // 日付が変わっていたら実行中タスクを解除して新しい日へ切り替える
    private func rolloverIfNeeded() {
        let today = todayKey()

        if lastCheckedDateKey.isEmpty {
            lastCheckedDateKey = UserDefaults.standard.string(forKey: lastActiveDateKeyStorageKey) ?? today
        }

        if lastCheckedDateKey != today {
            currentTaskID = nil
            startTime = nil
            clearActiveSession()
            lastCheckedDateKey = today
            UserDefaults.standard.set(today, forKey: lastActiveDateKeyStorageKey)
        } else {
            UserDefaults.standard.set(today, forKey: lastActiveDateKeyStorageKey)
            lastCheckedDateKey = today
        }
    }

    // MARK: - 保存/復元

    // タスク保存
    private func saveTasks() {
        if let encoded = try? JSONEncoder().encode(tasks) {
            UserDefaults.standard.set(encoded, forKey: tasksStorageKey)
        }
    }

    // 履歴保存
    private func saveHistory() {
        if let encoded = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(encoded, forKey: historyStorageKey)
        }
    }

    // 実行中セッション保存
    private func saveActiveSession() {
        guard let currentTaskID, let startTime else { return }

        let session = ActiveSession(
            taskID: currentTaskID,
            startTime: startTime,
            dateKey: todayKey()
        )

        if let encoded = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(encoded, forKey: activeSessionStorageKey)
        }
    }

    // 実行中セッション削除
    private func clearActiveSession() {
        UserDefaults.standard.removeObject(forKey: activeSessionStorageKey)
    }

    // 実行中セッション復元
    private func restoreActiveSession() {
        guard
            let data = UserDefaults.standard.data(forKey: activeSessionStorageKey),
            let session = try? JSONDecoder().decode(ActiveSession.self, from: data)
        else {
            UserDefaults.standard.set(todayKey(), forKey: lastActiveDateKeyStorageKey)
            lastCheckedDateKey = todayKey()
            return
        }

        let today = todayKey()
        lastCheckedDateKey = today
        UserDefaults.standard.set(today, forKey: lastActiveDateKeyStorageKey)

        guard session.dateKey == today else {
            clearActiveSession()
            currentTaskID = nil
            startTime = nil
            return
        }

        guard tasks.contains(where: { $0.id == session.taskID && !$0.isDone }) else {
            clearActiveSession()
            currentTaskID = nil
            startTime = nil
            return
        }

        currentTaskID = session.taskID
        startTime = session.startTime
    }

    // 保存済みタスク読み込み
    private static func loadTasks() -> [TaskItem] {
        guard
            let data = UserDefaults.standard.data(forKey: "randomTodo.tasks"),
            let decoded = try? JSONDecoder().decode([TaskItem].self, from: data)
        else {
            return []
        }
        return decoded
    }

    // 保存済み履歴読み込み
    private static func loadHistory() -> [DailyHistory] {
        guard
            let data = UserDefaults.standard.data(forKey: "randomTodo.history"),
            let decoded = try? JSONDecoder().decode([DailyHistory].self, from: data)
        else {
            return []
        }
        return decoded
    }

    // 日付フォーマッタ
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

// MARK: - ルート画面
// タブで3ページを切り替える
struct ContentView: View {
    @StateObject private var store = TaskStore()

    var body: some View {
        TabView {
            HomeView(store: store)
                .tabItem {
                    Label("ホーム", systemImage: "checklist")
                }

            HistoryView(store: store)
                .tabItem {
                    Label("履歴", systemImage: "clock.arrow.circlepath")
                }

            StreakView(store: store)
                .tabItem {
                    Label("ストリーク", systemImage: "flame")
                }
        }
        .frame(minWidth: 960, minHeight: 760)
    }
}

// MARK: - ホーム画面
// 今日のタスク操作の中心画面
struct HomeView: View {
    @ObservedObject var store: TaskStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                dashboardSection
                inputSection
                actionSection
                currentTaskSection
                taskListSection
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // アプリタイトルと説明
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ランダムTODOアプリ")
                .font(.largeTitle)
                .bold()

            Text("今日のタスクを絞り込み、1つずつ集中して片付けるためのワークスペース")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // 今日の達成率、完了数、作業時間を表示するダッシュボード
    private var dashboardSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("今日のダッシュボード")

            HStack(alignment: .top, spacing: 16) {
                metricCard(
                    title: "達成率",
                    value: "\(Int(store.completionRate * 100))%",
                    subtitle: "\(store.todayCompletedCount)件完了"
                ) {
                    ProgressView(value: store.completionRate)
                        .progressViewStyle(.linear)
                }

                metricCard(
                    title: "今日の完了数",
                    value: "\(store.todayCompletedCount)件",
                    subtitle: "完了済みタスク"
                )

                metricCard(
                    title: "今日の作業時間",
                    value: store.formattedTime(store.todayTotalSeconds),
                    subtitle: "累計計測時間"
                )
            }
        }
    }

    // タスク入力エリア
    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("タスク追加")

            HStack(spacing: 12) {
                TextField("今日やるタスクを入力", text: $store.inputText)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
                    .padding(.vertical, 2)

                Button {
                    store.addTask()
                } label: {
                    Label("追加", systemImage: "plus")
                        .frame(minWidth: 88)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    // 操作ボタン群
    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("操作")

            HStack(spacing: 12) {
                Button {
                    store.pickRandomTask()
                } label: {
                    Label("決定", systemImage: "shuffle")
                        .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(store.remainingTasks.isEmpty || store.currentTaskID != nil)

                Button {
                    store.completeCurrentTask()
                } label: {
                    Label("完了", systemImage: "checkmark.circle.fill")
                        .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.green)
                .disabled(store.currentTaskID == nil)

                Button {
                    store.clearRemainingTasks()
                } label: {
                    Label("未完了をクリア", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.red)
                .disabled(store.tasks.isEmpty)
            }
        }
    }

    // 現在実行中のタスク表示
    @ViewBuilder
    private var currentTaskSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("現在のフォーカス")

            if let currentTask = store.currentTask {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        statusPill(text: "実行中", color: .blue)
                        Spacer()
                        Text("計測中")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("今やるタスク")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Text(currentTask.title)
                        .font(.system(size: 28, weight: .bold))

                    Divider()

                    Text("このタスクを完了すると、次の未完了タスクが自動で選ばれます。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.blue.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
            } else if store.tasks.isEmpty {
                emptyStateCard(
                    title: "タスクを追加してください",
                    description: "まずは今日やることを入れて、ランダムに選べる状態にしましょう。"
                )
            } else if store.remainingTasks.isEmpty {
                emptyStateCard(
                    title: "すべて完了です",
                    description: "今日のタスクは完了しました。履歴とストリークも更新されています。",
                    accent: .green
                )
            } else {
                emptyStateCard(
                    title: "次のタスクを選べます",
                    description: "「決定」を押すと、未完了タスクからランダムに1件選ばれます。"
                )
            }
        }
    }

    // タスク一覧表示
    private var taskListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("今日のタスク")
                Spacer()
                Text("\(store.tasks.count)件")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if store.tasks.isEmpty {
                emptyStateCard(
                    title: "まだタスクがありません",
                    description: "上の入力欄から追加すると、ここに一覧表示されます。"
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(store.tasks) { task in
                        taskRow(task)
                    }
                }
            }
        }
    }

    // タスク1行分
    // 完了済みタスクには「繰り返す」ボタンを表示
    private func taskRow(_ task: TaskItem) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(taskAccentColor(task))
                .frame(width: 6)

            VStack(alignment: .leading, spacing: 6) {
                Text(task.title)
                    .font(.headline)
                    .strikethrough(task.isDone, color: .secondary)

                if task.isDone {
                    Text("所要時間: \(store.formattedTime(task.elapsedSeconds))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if store.currentTaskID == task.id {
                    Text("現在このタスクを計測中です")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("未着手")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                if store.currentTaskID == task.id {
                    statusPill(text: "実行中", color: .blue)
                } else if task.isDone {
                    statusPill(text: "完了", color: .green)

                    Button {
                        store.repeatTask(task)
                    } label: {
                        Label("繰り返す", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    statusPill(text: "未着手", color: .gray)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .contextMenu {
            Button(role: .destructive) {
                if let index = store.tasks.firstIndex(where: { $0.id == task.id }) {
                    store.deleteTasks(at: IndexSet(integer: index))
                }
            } label: {
                Label("削除", systemImage: "trash")
            }
        }
    }

    // ダッシュボード用カード
    private func metricCard<Content: View>(
        title: String,
        value: String,
        subtitle: String,
        @ViewBuilder content: () -> Content = { EmptyView() }
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 26, weight: .bold))

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    // セクションタイトル
    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.title3)
            .bold()
    }

    // 状態表示用のピル
    private func statusPill(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // 空状態表示用カード
    private func emptyStateCard(title: String, description: String, accent: Color = .secondary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(accent)

            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    // 左のアクセントカラー
    private func taskAccentColor(_ task: TaskItem) -> Color {
        if store.currentTaskID == task.id {
            return .blue
        } else if task.isDone {
            return .green
        } else {
            return .gray.opacity(0.6)
        }
    }
}

// MARK: - 履歴画面
struct HistoryView: View {
    @ObservedObject var store: TaskStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("履歴")
                            .font(.largeTitle)
                            .bold()

                        Text("日ごとの完了数と作業時間の記録")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("履歴を全削除") {
                        store.clearHistory()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(.red)
                    .disabled(store.history.isEmpty)
                }

                if store.sortedHistory.isEmpty {
                    historyEmptyState
                } else {
                    VStack(spacing: 14) {
                        ForEach(store.sortedHistory) { day in
                            historyCard(day)
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // 履歴が空の時の表示
    private var historyEmptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("まだ履歴はありません")
                .font(.headline)

            Text("タスクを完了すると、ここに日ごとの記録が蓄積されます。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    // 1日分の履歴カード
    private func historyCard(_ day: DailyHistory) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(day.dateKey)
                    .font(.title3)
                    .bold()

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(day.completedCount)件完了")
                        .font(.headline)
                    Text(store.formattedTime(day.totalSeconds))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(spacing: 10) {
                ForEach(day.completedTasks) { item in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color.green.opacity(0.8))
                            .frame(width: 8, height: 8)

                        Text(item.title)
                            .font(.body)

                        Spacer()

                        Text(store.formattedTime(item.elapsedSeconds))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

// MARK: - ストリーク画面
struct StreakView: View {
    @ObservedObject var store: TaskStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ストリーク")
                        .font(.largeTitle)
                        .bold()

                    Text("継続状況を確認して、日々の達成ペースを可視化")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 16) {
                    streakCard(
                        title: "現在の連続日数",
                        value: "\(store.streakCount)日",
                        subtitle: "今日まで連続で達成"
                    )

                    streakCard(
                        title: "最長ストリーク",
                        value: "\(store.longestStreak)日",
                        subtitle: "これまでの最高記録"
                    )

                    streakCard(
                        title: "最後に達成した日",
                        value: store.lastCompletedDateText,
                        subtitle: "直近の達成日"
                    )
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("直近7日")
                        .font(.title3)
                        .bold()

                    HStack(spacing: 12) {
                        ForEach(store.last7DaysStatus, id: \.dateKey) { item in
                            VStack(spacing: 8) {
                                Circle()
                                    .fill(item.didComplete ? Color.green : Color.gray.opacity(0.25))
                                    .overlay {
                                        if item.dateKey == store.todayKeyValue {
                                            Circle()
                                                .stroke(Color.blue, lineWidth: 2)
                                        }
                                    }
                                    .frame(width: 30, height: 30)

                                Text(String(item.dateKey.suffix(5)))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("見方")
                        .font(.headline)

                    Text("緑の丸はその日に1件以上の完了があったことを表します。青い枠は今日です。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.orange.opacity(0.08))
                )
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // ストリーク用カード
    private func streakCard(title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 24, weight: .bold))

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.orange.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - プレビュー
#Preview {
    ContentView()
}
