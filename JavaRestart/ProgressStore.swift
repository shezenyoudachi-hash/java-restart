import Foundation
import Observation

enum ReadState: String, Codable, Comparable {
    case reading
    case done

    static func < (a: ReadState, b: ReadState) -> Bool { a == .reading && b == .done }
}

struct AnswerRecord: Codable, Hashable {
    var correct: Bool
    var attempts: Int
}

/// 進捗の保存形式。端末内の保存と、端末間の同期の両方で使う
struct ProgressSnapshot: Codable, Equatable {
    var chapterStates: [Int: ReadState]
    var answers: [Int: AnswerRecord]
    var stepsDone: Set<Int>
    var activity: [String: Int]
    var lastChapter: Int?
    // ここから下は後から追加した項目。古い保存データには無いので optional
    var listened: Set<String>?
    /// 項目ごとの最終更新時刻（"ch-3"、"ans-5"、"step-2"、"listen-<id>"）。同期で新しい方を選ぶのに使う
    var stamps: [String: Date]?
    /// 「進捗をすべてリセット」した時刻。これより古い記録は同期でも戻さない
    var resetAt: Date?

    static let empty = ProgressSnapshot(chapterStates: [:], answers: [:], stepsDone: [], activity: [:],
                                        lastChapter: nil, listened: [], stamps: [:], resetAt: nil)

    /// 2台の進捗を合わせる。何度合わせても、どちらから合わせても同じ結果になる（lastChapter だけは a を優先）
    ///
    /// - 読了・回答・作って学ぶのステップ：後から変更した方を採用（時刻がなければ、進んでいる方）
    /// - 聞いたノート：どちらかで聞いていれば聞いた
    /// - 学習カレンダー：日ごとに多い方
    /// - リセット：新しい方のリセット時刻より前の記録は捨てる
    static func merge(_ a: ProgressSnapshot, _ b: ProgressSnapshot) -> ProgressSnapshot {
        let reset = [a.resetAt, b.resetAt].compactMap { $0 }.max()
        let sa = a.stamps ?? [:], sb = b.stamps ?? [:]

        /// リセットより後に記録されたものだけを有効にする
        func alive(_ stamps: [String: Date], _ key: String) -> Bool {
            guard let reset else { return true }
            guard let t = stamps[key] else { return false }
            return t > reset
        }
        func stamp(_ stamps: [String: Date], _ key: String) -> Date { stamps[key] ?? .distantPast }

        var out = ProgressSnapshot.empty
        out.resetAt = reset

        // 読了状態
        for id in Set(a.chapterStates.keys).union(b.chapterStates.keys) {
            let k = "ch-\(id)"
            let va = alive(sa, k) ? a.chapterStates[id] : nil
            let vb = alive(sb, k) ? b.chapterStates[id] : nil
            switch (va, vb) {
            case let (x?, y?):
                let ta = stamp(sa, k), tb = stamp(sb, k)
                out.chapterStates[id] = ta == tb ? max(x, y) : (ta > tb ? x : y)
            case let (x?, nil): out.chapterStates[id] = x
            case let (nil, y?): out.chapterStates[id] = y
            default: break
            }
        }

        // ドリルの回答
        for id in Set(a.answers.keys).union(b.answers.keys) {
            let k = "ans-\(id)"
            let va = alive(sa, k) ? a.answers[id] : nil
            let vb = alive(sb, k) ? b.answers[id] : nil
            switch (va, vb) {
            case let (x?, y?):
                let ta = stamp(sa, k), tb = stamp(sb, k)
                if ta != tb {
                    out.answers[id] = ta > tb ? x : y
                } else if x.attempts != y.attempts {
                    out.answers[id] = x.attempts > y.attempts ? x : y
                } else {
                    out.answers[id] = AnswerRecord(correct: x.correct || y.correct, attempts: x.attempts)
                }
            case let (x?, nil): out.answers[id] = x
            case let (nil, y?): out.answers[id] = y
            default: break
            }
        }

        // 作って学ぶのステップ（完了を取り消すこともあるので、時刻で決める）
        let stepIDs = Set(a.stepsDone).union(b.stepsDone)
            .union(Set(sa.keys).union(sb.keys).compactMap { $0.hasPrefix("step-") ? Int($0.dropFirst(5)) : nil })
        for id in stepIDs {
            let k = "step-\(id)"
            let da = alive(sa, k) && a.stepsDone.contains(id)
            let db = alive(sb, k) && b.stepsDone.contains(id)
            let ta = alive(sa, k) ? stamp(sa, k) : .distantPast
            let tb = alive(sb, k) ? stamp(sb, k) : .distantPast
            let done = ta == tb ? (da || db) : (ta > tb ? da : db)
            if done { out.stepsDone.insert(id) }
        }

        // 聞いたノート
        var heard = Set<String>()
        for id in a.listened ?? [] where alive(sa, "listen-\(id)") { heard.insert(id) }
        for id in b.listened ?? [] where alive(sb, "listen-\(id)") { heard.insert(id) }
        out.listened = heard

        // 学習カレンダー（リセットした日より前は捨てる）
        let resetDay = reset.map(ProgressStore.dayKey)
        for day in Set(a.activity.keys).union(b.activity.keys) {
            if let resetDay, day < resetDay { continue }
            out.activity[day] = max(a.activity[day] ?? 0, b.activity[day] ?? 0)
        }

        // 各項目の時刻は新しい方
        var stamps = sa
        for (k, t) in sb { stamps[k] = max(stamps[k] ?? .distantPast, t) }
        out.stamps = stamps

        out.lastChapter = a.lastChapter ?? b.lastChapter
        return out
    }
}

/// 学習の進捗。端末内（UserDefaults）に保存する。
@Observable
final class ProgressStore {
    private(set) var chapterStates: [Int: ReadState] = [:]
    private(set) var answers: [Int: AnswerRecord] = [:]
    private(set) var stepsDone: Set<Int> = []
    /// "yyyy-MM-dd" → その日の学習アクション数
    private(set) var activity: [String: Int] = [:]
    private(set) var lastChapter: Int?
    /// 最後まで聞いた学習ノートの id
    private(set) var listened: Set<String> = []
    @ObservationIgnored private var stamps: [String: Date] = [:]
    @ObservationIgnored private var resetAt: Date?

    /// 内容が変わって保存したときに呼ばれる（同期用）
    @ObservationIgnored var onChange: (() -> Void)?

    private let key = "progress.v1"

    init() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(ProgressSnapshot.self, from: data) else { return }
        load(s)
    }

    var snapshot: ProgressSnapshot {
        ProgressSnapshot(chapterStates: chapterStates, answers: answers, stepsDone: stepsDone,
                         activity: activity, lastChapter: lastChapter, listened: listened,
                         stamps: stamps, resetAt: resetAt)
    }

    private func load(_ s: ProgressSnapshot) {
        chapterStates = s.chapterStates
        answers = s.answers
        stepsDone = s.stepsDone
        activity = s.activity
        lastChapter = s.lastChapter
        listened = s.listened ?? []
        stamps = s.stamps ?? [:]
        resetAt = s.resetAt
    }

    private func save(notify: Bool = true) {
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: key)
        }
        if notify { onChange?() }
    }

    /// 別の端末の進捗を合わせる。内容が変わったら true
    @discardableResult
    func merge(_ other: ProgressSnapshot) -> Bool {
        let merged = ProgressSnapshot.merge(snapshot, other)
        guard merged != snapshot else { return false }
        load(merged)
        save(notify: false)   // 同期で受け取った変更は、すぐに送り返さない（送り返すかは同期側が決める）
        return true
    }

    private func touch(_ key: String) { stamps[key] = Date() }

    private func logActivity() {
        activity[Self.dayKey(Date()), default: 0] += 1
    }

    // MARK: - 操作

    func open(_ chapterID: Int) {
        var changed = false
        if chapterStates[chapterID] == nil {
            chapterStates[chapterID] = .reading
            touch("ch-\(chapterID)")
            logActivity()
            changed = true
        }
        if lastChapter != chapterID {
            lastChapter = chapterID
            changed = true
        }
        if changed { save() }
    }

    func setDone(_ chapterID: Int, _ done: Bool) {
        chapterStates[chapterID] = done ? .done : .reading
        touch("ch-\(chapterID)")
        if done { logActivity() }
        save()
    }

    func record(question: Question, choice: Int) {
        let correct = choice == question.a
        let prev = answers[question.id]
        answers[question.id] = AnswerRecord(correct: correct, attempts: (prev?.attempts ?? 0) + 1)
        touch("ans-\(question.id)")
        logActivity()
        save()
    }

    func toggleStep(_ id: Int) {
        if stepsDone.contains(id) {
            stepsDone.remove(id)
        } else {
            stepsDone.insert(id)
            logActivity()
        }
        touch("step-\(id)")
        save()
    }

    func markListened(_ noteID: String) {
        listened.insert(noteID)
        touch("listen-\(noteID)")
        logActivity()
        save()
    }

    func resetAll() {
        chapterStates = [:]
        answers = [:]
        stepsDone = []
        activity = [:]
        lastChapter = nil
        listened = []
        stamps = [:]
        resetAt = Date()
        save()
    }

    // MARK: - 集計

    func state(of chapterID: Int) -> ReadState? { chapterStates[chapterID] }

    var doneChapterCount: Int { chapterStates.values.filter { $0 == .done }.count }

    var bookRatio: Double {
        Content.chapters.isEmpty ? 0 : Double(doneChapterCount) / Double(Content.chapters.count)
    }

    func doneCount(in part: Part) -> Int {
        Content.chapters(in: part).filter { chapterStates[$0.id] == .done }.count
    }

    func correctCount(_ questions: [Question]) -> Int {
        questions.filter { answers[$0.id]?.correct == true }.count
    }

    var totalCorrect: Int { correctCount(Content.questions) }

    /// 次に読む章：読了していない最初の章
    var nextChapter: Chapter? {
        Content.chapters.first { chapterStates[$0.id] != .done }
    }

    var studyDayCount: Int { activity.filter { $0.value > 0 }.count }

    /// 今日（今日まだなら昨日）から遡った連続学習日数
    var streak: Int {
        let cal = Calendar.current
        var day = cal.startOfDay(for: Date())
        if (activity[Self.dayKey(day)] ?? 0) == 0 {
            guard let y = cal.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = y
        }
        var count = 0
        while (activity[Self.dayKey(day)] ?? 0) > 0 {
            count += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return count
    }

    func activityCount(on date: Date) -> Int { activity[Self.dayKey(date)] ?? 0 }

    static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
