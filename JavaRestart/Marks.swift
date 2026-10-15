import SwiftUI
import Observation

// MARK: - データ

/// 「わからない」マーク。参考書の本文の1ブロック、または台本の1段落に付ける
struct StudyMark: Codable, Identifiable, Hashable {
    enum Kind: String, Codable { case book, script }

    /// 付けた場所を表すキー（参考書: "book-章-節-ブロック"、台本: "script-台本id-段落"）
    let id: String
    let kind: Kind
    /// 参考書の章（台本のマークでは nil）
    let chapterID: Int?
    /// 台本の id（学習ノートの id、または参考書の章の台本 "book-N"）
    let scriptID: String?
    /// 一覧のグループ名（例: 第2章 データ型と変数）
    let group: String
    /// グループの中の場所（例: 型変換とキャスト）
    let place: String
    /// マークした箇所の文章（コードはそのまま）
    let excerpt: String
    let isCode: Bool
    var memo: String
    let createdAt: Date
    var resolvedAt: Date?
    /// メモや解決済みを変えた時刻（同期で新しい方を選ぶ）。古い保存データには無いので optional
    var updatedAt: Date?

    var isResolved: Bool { resolvedAt != nil }
    var lastChanged: Date { updatedAt ?? createdAt }

    /// 2台のマークを合わせる。マークごとに新しい方を採用し、削除した記録より古いマークは消す
    static func merge(_ a: [StudyMark], _ deletedA: [String: Date],
                      _ b: [StudyMark], _ deletedB: [String: Date]) -> (marks: [StudyMark], deleted: [String: Date]) {
        var deleted = deletedA
        for (k, t) in deletedB { deleted[k] = max(deleted[k] ?? .distantPast, t) }

        var byID: [String: StudyMark] = [:]
        for m in a + b {
            if let cur = byID[m.id] {
                // 新しい方。同時刻なら内容で決めて、どちらから合わせても同じ結果にする
                let resolvedM = m.resolvedAt ?? .distantPast, resolvedC = cur.resolvedAt ?? .distantPast
                if (m.lastChanged, resolvedM, m.memo) > (cur.lastChanged, resolvedC, cur.memo) {
                    byID[m.id] = m
                }
            } else {
                byID[m.id] = m
            }
        }
        let alive = byID.values.filter { m in
            guard let d = deleted[m.id] else { return true }
            return m.lastChanged > d
        }
        return (alive.sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }, deleted)
    }
}

/// マークの保存先。端末内（UserDefaults）に保存する
@Observable
final class MarkStore {
    private(set) var marks: [StudyMark] = []
    /// 削除したマークの id と削除した時刻（同期で、他の端末から復活しないようにする）
    @ObservationIgnored private(set) var deleted: [String: Date] = [:]
    /// 一覧から「この箇所を開く」を押したとき、章の画面でスクロールする先
    var pendingFocus: String?

    /// 内容が変わって保存したときに呼ばれる（同期用）
    @ObservationIgnored var onChange: (() -> Void)?

    private let key = "marks.v1"
    private let deletedKey = "marks.deleted.v1"

    init() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: key), let saved = try? JSONDecoder().decode([StudyMark].self, from: data) {
            marks = saved
        }
        if let data = d.data(forKey: deletedKey), let saved = try? JSONDecoder().decode([String: Date].self, from: data) {
            deleted = saved
        }
    }

    private func save(notify: Bool = true) {
        let enc = JSONEncoder()
        if let data = try? enc.encode(marks) { UserDefaults.standard.set(data, forKey: key) }
        if let data = try? enc.encode(deleted) { UserDefaults.standard.set(data, forKey: deletedKey) }
        if notify { onChange?() }
    }

    /// 別の端末のマークを合わせる。内容が変わったら true
    @discardableResult
    func merge(_ other: [StudyMark], deleted otherDeleted: [String: Date]) -> Bool {
        let r = StudyMark.merge(marks, deleted, other, otherDeleted)
        guard Set(r.marks) != Set(marks) || r.deleted != deleted else { return false }
        marks = r.marks
        deleted = r.deleted
        save(notify: false)
        return true
    }

    func mark(for key: String) -> StudyMark? { marks.first { $0.id == key } }
    func isMarked(_ key: String) -> Bool { mark(for: key) != nil }

    var open: [StudyMark] { marks.filter { !$0.isResolved }.sorted { $0.createdAt < $1.createdAt } }
    var resolved: [StudyMark] {
        marks.filter(\.isResolved).sorted { ($0.resolvedAt ?? .distantPast) > ($1.resolvedAt ?? .distantPast) }
    }

    func add(_ target: MarkTarget, memo: String) {
        let trimmed = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        if let i = marks.firstIndex(where: { $0.id == target.key }) {
            // 解決済みの箇所にもう一度マークしたときは、未解決に戻してメモを更新する
            marks[i].memo = trimmed
            marks[i].resolvedAt = nil
            marks[i].updatedAt = now
        } else {
            marks.append(StudyMark(id: target.key, kind: target.kind, chapterID: target.chapterID,
                                   scriptID: target.scriptID, group: target.group, place: target.place,
                                   excerpt: target.excerpt, isCode: target.isCode, memo: trimmed,
                                   createdAt: now, resolvedAt: nil, updatedAt: now))
        }
        save()
    }

    func setMemo(_ key: String, _ memo: String) {
        guard let i = marks.firstIndex(where: { $0.id == key }) else { return }
        marks[i].memo = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        marks[i].updatedAt = Date()
        save()
    }

    func setResolved(_ key: String, _ resolved: Bool) {
        guard let i = marks.firstIndex(where: { $0.id == key }) else { return }
        let now = Date()
        marks[i].resolvedAt = resolved ? now : nil
        marks[i].updatedAt = now
        save()
    }

    func resolveAllOpen() {
        let now = Date()
        for i in marks.indices where marks[i].resolvedAt == nil {
            marks[i].resolvedAt = now
            marks[i].updatedAt = now
        }
        save()
    }

    func remove(_ key: String) {
        marks.removeAll { $0.id == key }
        deleted[key] = Date()
        save()
    }

    func removeAll() {
        let now = Date()
        for m in marks { deleted[m.id] = now }
        marks = []
        save()
    }

    /// Claude にそのまま貼り付けられる質問文
    static func questionText(for marks: [StudyMark]) -> String {
        var lines: [String] = [
            "Javaリスタートで「わからない」にマークした箇所です（\(marks.count)件）。",
            "それぞれ、つまずいている点が分かるように詳しく解説してください。解説が終わったら、学習ノートとアプリの台本にも追記してください。",
            ""
        ]
        for (i, m) in marks.enumerated() {
            lines.append("\(i + 1). \(m.group) ＞ \(m.place)")
            if m.isCode {
                lines.append("本文（コード）：")
                lines.append("```java")
                lines.append(m.excerpt)
                lines.append("```")
            } else {
                lines.append("本文：「\(m.excerpt)」")
            }
            lines.append("分からない点：\(m.memo.isEmpty ? "（メモなし。この箇所全体を解説してほしい）" : m.memo)")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - マークする対象

/// マークを付けられる1か所の情報
struct MarkTarget {
    let key: String
    let kind: StudyMark.Kind
    let chapterID: Int?
    let scriptID: String?
    let group: String
    let place: String
    let excerpt: String
    let isCode: Bool

    /// 参考書の本文のブロック
    static func book(_ ch: Chapter, place: String, key: String, block: Block) -> MarkTarget {
        let (text, code) = Self.plain(block)
        return MarkTarget(key: "book-\(ch.id)-\(key)", kind: .book, chapterID: ch.id, scriptID: nil,
                          group: "参考書 第\(ch.id)章 \(ch.t)", place: place, excerpt: text, isCode: code)
    }

    /// 参考書の要点・落とし穴・導入文など、1つの文
    static func book(_ ch: Chapter, place: String, key: String, text: String) -> MarkTarget {
        MarkTarget(key: "book-\(ch.id)-\(key)", kind: .book, chapterID: ch.id, scriptID: nil,
                   group: "参考書 第\(ch.id)章 \(ch.t)", place: place, excerpt: Self.stripMarkdown(text), isCode: false)
    }

    /// 台本の1段落（学習ノート・参考書の章の台本）
    static func script(_ note: ListenNote, paragraph i: Int) -> MarkTarget {
        let isBook = note.id.hasPrefix("book-")
        return MarkTarget(key: "script-\(note.id)-\(i)", kind: .script, chapterID: note.chapter, scriptID: note.id,
                          group: isBook ? "参考書の台本 \(note.title)" : "学習ノート「\(note.title)」",
                          place: "段落 \(i + 1)", excerpt: note.script[i], isCode: false)
    }

    private static func plain(_ block: Block) -> (String, Bool) {
        switch block {
        case .paragraph(let t):
            return (stripMarkdown(t), false)
        case .list(let items):
            return (items.map { "・" + stripMarkdown($0) }.joined(separator: "\n"), false)
        case .table(let header, let rows):
            let all = [header] + rows
            return (all.map { $0.map(stripMarkdown).joined(separator: " | ") }.joined(separator: "\n"), false)
        case .code(let c):
            return (c, true)
        }
    }

    static func stripMarkdown(_ s: String) -> String {
        s.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
    }
}

// MARK: - マークできる部品

extension View {
    /// 長押しで「わからない」マークを付け外しできるようにする
    func markable(_ target: MarkTarget) -> some View {
        MarkableHost(wrapped: self, target: target)
    }
}

/// （ViewModifier はアプリのデータ型 Content と名前がぶつかるので使わない）
struct MarkableHost<Wrapped: View>: View {
    @Environment(MarkStore.self) private var marks
    let wrapped: Wrapped
    let target: MarkTarget

    @State private var editing = false
    @State private var memo = ""

    var body: some View {
        let current = marks.mark(for: target.key)
        let active = current.map { !$0.isResolved } ?? false
        wrapped
            .padding(.leading, active ? 12 : 0)
            .overlay(alignment: .leading) {
                if active {
                    RoundedRectangle(cornerRadius: 2).fill(Palette.mark).frame(width: 4)
                }
            }
            .overlay(alignment: .topTrailing) {
                if active {
                    Button {
                        memo = current?.memo ?? ""
                        editing = true
                    } label: {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.body)
                            .foregroundStyle(Palette.mark)
                            .background(Circle().fill(Color(.systemBackground)))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 6, y: -8)
                    .accessibilityLabel("わからないマークのメモ")
                }
            }
            .contentShape(Rectangle())
            .contextMenu {
                if active {
                    Button("メモを編集", systemImage: "square.and.pencil") {
                        memo = current?.memo ?? ""
                        editing = true
                    }
                    Button("わかった（解決済みにする）", systemImage: "checkmark.circle") {
                        marks.setResolved(target.key, true)
                    }
                    Button("マークを外す", systemImage: "xmark.circle", role: .destructive) {
                        marks.remove(target.key)
                    }
                } else {
                    Button("わからないにマーク", systemImage: "questionmark.circle") {
                        memo = ""
                        editing = true
                    }
                }
            }
            .alert(active ? "メモを編集" : "わからないにマーク", isPresented: $editing) {
                TextField("どこが分からない？（空欄でもOK）", text: $memo)
                Button(active ? "保存" : "マークする") {
                    if active {
                        marks.setMemo(target.key, memo)
                    } else {
                        marks.add(target, memo: memo)
                    }
                }
                Button("キャンセル", role: .cancel) { }
            } message: {
                Text(String(target.excerpt.prefix(80)) + (target.excerpt.count > 80 ? "…" : ""))
            }
    }
}

/// ツールバーに置く「わからない」ボタン（未解決の件数つき）
struct MarksToolbarButton: View {
    @Environment(MarkStore.self) private var marks
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: "questionmark.bubble")
                if !marks.open.isEmpty {
                    Text("\(marks.open.count)").font(.caption.bold()).monospacedDigit()
                }
            }
        }
        .accessibilityLabel("わからない一覧（未解決 \(marks.open.count) 件）")
    }
}
