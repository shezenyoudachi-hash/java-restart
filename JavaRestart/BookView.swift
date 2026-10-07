import SwiftUI

struct BookView: View {
    @Environment(ProgressStore.self) private var store
    @Binding var path: [Int]
    let openQuiz: (Chapter) -> Void

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    BookProgressHeader { path = [$0] }
                }
                ForEach(Content.parts) { part in
                    Section {
                        ForEach(Content.chapters(in: part)) { ch in
                            NavigationLink(value: ch.id) {
                                ChapterRow(chapter: ch)
                            }
                        }
                    } header: {
                        PartHeader(part: part)
                    }
                }
            }
            .navigationTitle("参考書")
            .navigationDestination(for: Int.self) { id in
                if let ch = Content.chapter(id) {
                    ChapterView(chapter: ch,
                                go: { path = [$0] },
                                openQuiz: openQuiz)
                }
            }
        }
    }
}

// MARK: - 一覧の部品

private struct BookProgressHeader: View {
    @Environment(ProgressStore.self) private var store
    let open: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 18) {
                ProgressRing(value: store.bookRatio)
                    .frame(width: 84, height: 84)
                VStack(alignment: .leading, spacing: 6) {
                    Label("読了 \(store.doneChapterCount) / \(Content.chapters.count) 章", systemImage: "book.closed")
                    Label("確認問題 \(store.totalCorrect) / \(Content.questions.count) 問正解", systemImage: "checkmark.circle")
                    Label("連続 \(store.streak) 日・累計 \(store.studyDayCount) 日", systemImage: "flame")
                }
                .font(.subheadline)
                .monospacedDigit()
            }
            if let next = store.nextChapter {
                Button {
                    open(next.id)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.state(of: next.id) == .reading ? "続きから読む" : "次に読む")
                                .font(.caption).foregroundStyle(.white.opacity(0.85))
                            Text("第\(next.id)章 \(next.t)").font(.headline).foregroundStyle(.white)
                        }
                        Spacer()
                        Image(systemName: "arrow.right").foregroundStyle(.white)
                    }
                    .padding(12)
                    .background(Palette.accent, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            } else {
                Text("全17章を読了しました。ドリルで仕上げましょう。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct PartHeader: View {
    @Environment(ProgressStore.self) private var store
    let part: Part

    var body: some View {
        let total = Content.chapters(in: part).count
        let done = store.doneCount(in: part)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("第\(part.n)部  \(part.t)").font(.subheadline.bold()).foregroundStyle(.primary)
                Spacer()
                Text("\(done) / \(total)").font(.caption).monospacedDigit()
            }
            ProgressView(value: Double(done), total: Double(max(total, 1)))
        }
        .textCase(nil)
        .padding(.vertical, 4)
    }
}

private struct ChapterRow: View {
    @Environment(ProgressStore.self) private var store
    let chapter: Chapter

    var body: some View {
        let state = store.state(of: chapter.id)
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .strokeBorder(Palette.accent, lineWidth: 1.5)
                    .background(Circle().fill(state == .done ? Palette.accent : .clear))
                if state == .done {
                    Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                } else {
                    Text("\(chapter.id)").font(.caption.bold()).foregroundStyle(Palette.accent)
                }
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(chapter.t).font(.body.weight(.medium))
                Text(chapter.sum).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                if state == .reading {
                    Text("読書中").font(.caption2).foregroundStyle(Palette.accent)
                }
                if !chapter.quiz.isEmpty {
                    let qs = Content.questions.filter { chapter.quiz.contains($0.id) }
                    Text("\(store.correctCount(qs))/\(qs.count)問")
                        .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 章の本文

struct ChapterView: View {
    @Environment(ProgressStore.self) private var store
    let chapter: Chapter
    let go: (Int) -> Void
    let openQuiz: (Chapter) -> Void

    var body: some View {
        let done = store.state(of: chapter.id) == .done
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    toc(proxy: proxy)
                    ForEach(chapter.secs) { sec in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(sec.h).font(.title3.bold())
                            ForEach(Array(sec.blocks.enumerated()), id: \.offset) { _, block in
                                BlockView(block: block)
                            }
                        }
                        .id(sec.h)
                    }
                    summaryBox(title: "要点", icon: "lightbulb", items: chapter.points, tint: Palette.accent)
                    if !chapter.traps.isEmpty {
                        summaryBox(title: "落とし穴", icon: "exclamationmark.triangle", items: chapter.traps, tint: .orange)
                    }
                    footer(done: done)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("第\(chapter.id)章")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { store.open(chapter.id) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let part = Content.part(chapter.part) {
                Text("第\(part.n)部 \(part.t)").font(.caption.weight(.semibold)).foregroundStyle(Palette.accent)
            }
            Text(chapter.t).font(.title.bold())
            Text(md(chapter.lead)).foregroundStyle(.secondary).lineSpacing(4)
        }
    }

    private func toc(proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("この章の内容").font(.caption.bold()).foregroundStyle(.secondary)
            ForEach(Array(chapter.secs.enumerated()), id: \.offset) { i, sec in
                Button {
                    withAnimation { proxy.scrollTo(sec.h, anchor: .top) }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(chapter.id).\(i + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Text(sec.h).font(.subheadline)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Palette.codeBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
    }

    private func summaryBox(title: String, icon: String, items: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.headline).foregroundStyle(tint)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•").foregroundStyle(tint)
                    Text(md(item)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(tint.opacity(0.3)))
    }

    private func footer(done: Bool) -> some View {
        VStack(spacing: 12) {
            Button {
                store.setDone(chapter.id, !done)
            } label: {
                Label(done ? "読了済み（タップで取り消し）" : "この章を読了にする",
                      systemImage: done ? "checkmark.circle.fill" : "circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(done ? .gray : Palette.accent)
            .controlSize(.large)

            if !chapter.quiz.isEmpty {
                Button {
                    openQuiz(chapter)
                } label: {
                    Label("確認問題を解く（\(chapter.quiz.count)問）", systemImage: "pencil.and.list.clipboard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            HStack {
                if let prev = Content.chapter(chapter.id - 1) {
                    Button { go(prev.id) } label: {
                        Label("第\(prev.id)章", systemImage: "chevron.left")
                    }
                }
                Spacer()
                if let next = Content.chapter(chapter.id + 1) {
                    Button { go(next.id) } label: {
                        HStack(spacing: 4) {
                            Text("第\(next.id)章 \(next.t)").lineLimit(1)
                            Image(systemName: "chevron.right")
                        }
                    }
                }
            }
            .font(.subheadline)
            .padding(.top, 4)
        }
        .padding(.top, 8)
    }
}
