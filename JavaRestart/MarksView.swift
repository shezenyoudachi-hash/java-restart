import SwiftUI
import UIKit

/// 「わからない」にマークした箇所の一覧。まとめて Claude に質問するための文章も作る
struct MarksView: View {
    @Environment(MarkStore.self) private var marks
    @Environment(ProgressStore.self) private var store
    @Environment(SpeechPlayer.self) private var player
    @Environment(\.dismiss) private var dismiss

    /// 参考書の章を開く（一覧を閉じてから呼ばれる）
    let openChapter: (Int) -> Void

    @State private var showResolved = false
    @State private var copied = false
    @State private var scriptToShow: ListenNote?
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("表示", selection: $showResolved) {
                        Text("未解決 \(marks.open.count)").tag(false)
                        Text("解決済み \(marks.resolved.count)").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                if !showResolved && !marks.open.isEmpty {
                    Section {
                        askBox
                    }
                }

                let items = showResolved ? marks.resolved : marks.open
                if items.isEmpty {
                    Section {
                        emptyState
                    }
                } else {
                    ForEach(groups(items), id: \.name) { g in
                        Section(g.name) {
                            ForEach(g.items) { m in
                                MarkRow(mark: m)
                                    .contentShape(Rectangle())
                                    .onTapGesture { open(m) }
                                    .swipeActions(edge: .trailing) {
                                        Button("削除", systemImage: "trash", role: .destructive) {
                                            marks.remove(m.id)
                                        }
                                    }
                                    .swipeActions(edge: .leading) {
                                        if m.isResolved {
                                            Button("未解決に戻す", systemImage: "arrow.uturn.backward") {
                                                marks.setResolved(m.id, false)
                                            }
                                            .tint(Palette.mark)
                                        } else {
                                            Button("わかった", systemImage: "checkmark") {
                                                marks.setResolved(m.id, true)
                                            }
                                            .tint(Palette.ok)
                                        }
                                    }
                            }
                        }
                    }
                }
            }
            .navigationTitle("わからない")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        if !marks.open.isEmpty {
                            Button("未解決をすべて解決済みにする", systemImage: "checkmark.circle") {
                                marks.resolveAllOpen()
                            }
                        }
                        if !marks.marks.isEmpty {
                            Button("すべてのマークを削除", systemImage: "trash", role: .destructive) {
                                confirmClear = true
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .disabled(marks.marks.isEmpty)
                }
            }
            .confirmationDialog("未解決・解決済みのマークをすべて削除します。元に戻せません。",
                                isPresented: $confirmClear, titleVisibility: .visible) {
                Button("削除する", role: .destructive) { marks.removeAll() }
            }
            .sheet(item: $scriptToShow) { note in
                NavigationStack {
                    NoteDetailView(note: note,
                                   series: note.id.hasPrefix("book-") ? BookAudio.tracks : NotesContent.playOrder,
                                   openChapter: nil)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("閉じる") { scriptToShow = nil }
                            }
                        }
                }
                .environment(marks)
                .environment(store)
                .environment(player)
            }
        }
    }

    // MARK: まとめて質問

    private var askBox: some View {
        let text = MarkStore.questionText(for: marks.open)
        return VStack(alignment: .leading, spacing: 10) {
            Label("まとめて解説してもらう", systemImage: "sparkles")
                .font(.headline)
            Text("未解決の \(marks.open.count) 件を、Claude に貼り付ければそのまま使える質問文にします。解説を読んで分かったら、項目を右にスワイプして「わかった」にしてください。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button {
                    UIPasteboard.general.string = text
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                } label: {
                    Label(copied ? "コピーしました" : "質問文をコピー",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                ShareLink(item: text) {
                    Label("共有", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.regular)
        }
        .padding(.vertical, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: showResolved ? "checkmark.seal" : "questionmark.bubble")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(showResolved ? "解決済みのマークはまだありません" : "未解決のマークはありません")
                .font(.headline)
            if !showResolved {
                Text("参考書の本文や、学習ノートの台本の段落を長押しして「わからないにマーク」を選ぶと、ここに集まります。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: 並べ方と移動

    private struct MarkGroup { let name: String; let items: [StudyMark] }

    /// 最初にマークした順にグループを並べ、グループの中もマークした順
    private func groups(_ items: [StudyMark]) -> [MarkGroup] {
        var order: [String] = []
        var dict: [String: [StudyMark]] = [:]
        for m in items {
            if dict[m.group] == nil { order.append(m.group) }
            dict[m.group, default: []].append(m)
        }
        return order.map { MarkGroup(name: $0, items: dict[$0] ?? []) }
    }

    private func open(_ m: StudyMark) {
        switch m.kind {
        case .book:
            guard let ch = m.chapterID else { return }
            marks.pendingFocus = m.id
            dismiss()
            openChapter(ch)
        case .script:
            guard let id = m.scriptID else { return }
            scriptToShow = NotesContent.playOrder.first { $0.id == id } ?? BookAudio.tracks.first { $0.id == id }
        }
    }
}

private struct MarkRow: View {
    let mark: StudyMark

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: mark.isResolved ? "checkmark.circle.fill" : "questionmark.circle.fill")
                    .foregroundStyle(mark.isResolved ? Palette.ok : Palette.mark)
                Text(mark.place).font(.caption.weight(.semibold))
                Spacer()
                Text(mark.createdAt, format: .dateTime.month().day())
                    .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
            }
            Group {
                if mark.isCode {
                    Text(mark.excerpt).font(.system(.caption, design: .monospaced))
                } else {
                    Text(mark.excerpt).font(.subheadline)
                }
            }
            .lineLimit(3)
            .foregroundStyle(.primary)
            if !mark.memo.isEmpty {
                Text(mark.memo)
                    .font(.caption)
                    .foregroundStyle(Palette.mark)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Palette.mark.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.vertical, 2)
    }
}
