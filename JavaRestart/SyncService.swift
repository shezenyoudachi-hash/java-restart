import Foundation
import Observation
import UIKit

/// 端末間でやり取りする進捗一式
struct SyncPayload: Codable {
    var app = "JavaRestart"
    var version = 1
    var exportedAt: Date
    var device: String
    var progress: ProgressSnapshot
    var marks: [StudyMark]
    var deletedMarks: [String: Date]
}

/// 読み込み・同期で何が増えたか
struct MergeSummary {
    var chaptersDone = 0
    var answers = 0
    var listened = 0
    var openMarks = 0
    var changed = false

    var message: String {
        guard changed else { return "新しい内容はありませんでした。この端末はすでに最新です。" }
        var parts: [String] = []
        if chaptersDone != 0 { parts.append("読了 \(signed(chaptersDone)) 章") }
        if answers != 0 { parts.append("回答した問題 \(signed(answers)) 問") }
        if listened != 0 { parts.append("聞いたノート \(signed(listened)) 本") }
        if openMarks != 0 { parts.append("未解決のマーク \(signed(openMarks)) 件") }
        return parts.isEmpty ? "進捗を合わせました。" : "進捗を合わせました：" + parts.joined(separator: "、")
    }

    private func signed(_ n: Int) -> String { n > 0 ? "+\(n)" : "\(n)" }
}

enum SyncError: LocalizedError {
    case notOurFile

    var errorDescription: String? {
        switch self {
        case .notOurFile: return "Javaリスタートの進捗ファイルではありません。「進捗を書き出す」で作ったファイルを選んでください。"
        }
    }
}

/// 進捗の書き出し・読み込み（A）と、iCloud での自動同期（B）
@Observable
final class SyncService {
    enum CloudState: Equatable {
        case off
        case on
        case unavailable(String)
    }

    private(set) var cloudState: CloudState = .off
    private(set) var lastCloudSync: Date?

    private let store: ProgressStore
    private let marks: MarkStore
    private let kvs = NSUbiquitousKeyValueStore.default
    @ObservationIgnored private var uploadWork: DispatchWorkItem?
    @ObservationIgnored private var observer: NSObjectProtocol?

    private static let cloudKey = "payload.v1"
    private static let enabledKey = "sync.icloud.enabled"
    /// iCloud のキー値ストアは全体で 1MB まで
    private static let cloudLimit = 1_000_000

    init(store: ProgressStore, marks: MarkStore) {
        self.store = store
        self.marks = marks
        store.onChange = { [weak self] in self?.scheduleUpload() }
        marks.onChange = { [weak self] in self?.scheduleUpload() }
        if UserDefaults.standard.bool(forKey: Self.enabledKey) {
            startCloud()
        }
    }

    // MARK: - 共通

    func makePayload() -> SyncPayload {
        SyncPayload(exportedAt: Date(), device: UIDevice.current.name,
                    progress: store.snapshot, marks: marks.marks, deletedMarks: marks.deleted)
    }

    @discardableResult
    func apply(_ p: SyncPayload) -> MergeSummary {
        let before = counts()
        let a = store.merge(p.progress)
        let b = marks.merge(p.marks, deleted: p.deletedMarks)
        let after = counts()
        return MergeSummary(chaptersDone: after.0 - before.0, answers: after.1 - before.1,
                            listened: after.2 - before.2, openMarks: after.3 - before.3, changed: a || b)
    }

    private func counts() -> (Int, Int, Int, Int) {
        (store.doneChapterCount, store.answers.count, store.listened.count, marks.open.count)
    }

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }

    // MARK: - A. 書き出し・読み込み

    /// 進捗をファイルに書き出して、その場所を返す（共有シートで AirDrop などに渡す）
    func exportFile() throws -> URL {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyyMMdd-HHmm"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Javaリスタート進捗-\(f.string(from: Date())).json")
        let data = try Self.encoder().encode(makePayload())
        try data.write(to: url, options: .atomic)
        return url
    }

    /// 書き出したファイルを読み込んで、この端末の進捗と合わせる
    func importFile(at url: URL) throws -> MergeSummary {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard let p = try? JSONDecoder().decode(SyncPayload.self, from: data), p.app == "JavaRestart" else {
            throw SyncError.notOurFile
        }
        let summary = apply(p)
        if summary.changed { scheduleUpload() }   // iCloud 同期中なら、合わせた結果をもう一方へも送る
        return summary
    }

    // MARK: - B. iCloud 自動同期

    func setCloud(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        if on { startCloud() } else { stopCloud() }
    }

    private func startCloud() {
        guard FileManager.default.ubiquityIdentityToken != nil else {
            cloudState = .unavailable("この iPhone で iCloud にサインインしていません。設定アプリの一番上から Apple アカウントにサインインしてください。")
            return
        }
        // 必要な設定（有料の開発者登録と iCloud の設定）がないアプリでは false が返る
        guard kvs.synchronize() else {
            cloudState = .unavailable("このアプリでは、まだ iCloud を使えません。有料の Apple Developer Program に登録し、Xcode で iCloud（Key-value storage）をオンにすると使えるようになります。")
            return
        }
        if observer == nil {
            observer = NotificationCenter.default.addObserver(
                forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: kvs, queue: .main) { [weak self] _ in
                    self?.pullFromCloud()
                }
        }
        cloudState = .on
        pullFromCloud()
    }

    /// アプリが前面に戻ったときに呼ぶ。iCloud 側の新しい内容を取りに行く
    func refresh() {
        guard cloudState == .on else { return }
        kvs.synchronize()
        pullFromCloud()
    }

    private func stopCloud() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        uploadWork?.cancel()
        cloudState = .off
    }

    /// iCloud にある進捗を読んで合わせる。こちらにしかない内容があれば送り返す
    private func pullFromCloud() {
        guard cloudState == .on else { return }
        if let data = kvs.data(forKey: Self.cloudKey),
           let remote = try? JSONDecoder().decode(SyncPayload.self, from: data) {
            apply(remote)
            let mine = makePayload()
            let remoteHasAll = ProgressSnapshot.merge(remote.progress, mine.progress) == remote.progress
                && Set(StudyMark.merge(remote.marks, remote.deletedMarks, mine.marks, mine.deletedMarks).marks) == Set(remote.marks)
            if !remoteHasAll { upload() }
        } else {
            upload()   // まだ iCloud に何もない（この端末が最初）
        }
        lastCloudSync = Date()
    }

    /// 変更が続いたときにまとめて送るため、少し待ってから送る
    private func scheduleUpload() {
        guard cloudState == .on else { return }
        uploadWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.upload() }
        uploadWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    private func upload() {
        guard cloudState == .on else { return }
        // 送る直前にも iCloud 側を合わせておき、もう一方の変更を上書きしない
        if let data = kvs.data(forKey: Self.cloudKey),
           let remote = try? JSONDecoder().decode(SyncPayload.self, from: data) {
            apply(remote)
        }
        guard let data = try? Self.encoder().encode(makePayload()) else { return }
        guard data.count < Self.cloudLimit else {
            cloudState = .unavailable("進捗のデータが iCloud の上限（1MB）を超えました。書き出し・読み込みで同期してください。")
            return
        }
        kvs.set(data, forKey: Self.cloudKey)
        kvs.synchronize()
        lastCloudSync = Date()
    }
}
