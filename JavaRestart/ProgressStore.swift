import Foundation
import Observation

enum ReadState: String, Codable {
    case reading
    case done
}

struct AnswerRecord: Codable, Hashable {
    var correct: Bool
    var attempts: Int
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

    private struct Snapshot: Codable {
        var chapterStates: [Int: ReadState]
        var answers: [Int: AnswerRecord]
        var stepsDone: Set<Int>
        var activity: [String: Int]
        var lastChapter: Int?
    }

    private let key = "progress.v1"

    init() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        chapterStates = s.chapterStates
        answers = s.answers
        stepsDone = s.stepsDone
        activity = s.activity
        lastChapter = s.lastChapter
    }

    private func save() {
        let s = Snapshot(chapterStates: chapterStates, answers: answers, stepsDone: stepsDone,
                         activity: activity, lastChapter: lastChapter)
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func logActivity() {
        activity[Self.dayKey(Date()), default: 0] += 1
    }

    // MARK: - 操作

    func open(_ chapterID: Int) {
        if chapterStates[chapterID] == nil {
            chapterStates[chapterID] = .reading
            logActivity()
        }
        lastChapter = chapterID
        save()
    }

    func setDone(_ chapterID: Int, _ done: Bool) {
        chapterStates[chapterID] = done ? .done : .reading
        if done { logActivity() }
        save()
    }

    func record(question: Question, choice: Int) {
        let correct = choice == question.a
        let prev = answers[question.id]
        answers[question.id] = AnswerRecord(correct: correct, attempts: (prev?.attempts ?? 0) + 1)
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
        save()
    }

    func resetAll() {
        chapterStates = [:]
        answers = [:]
        stepsDone = []
        activity = [:]
        lastChapter = nil
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
