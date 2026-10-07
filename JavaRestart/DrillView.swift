import SwiftUI

enum DrillScope: Hashable {
    case all
    case category(String)
    case chapter(Int)
    case wrongOnly

    var title: String {
        switch self {
        case .all: return "全問"
        case .category(let c): return c
        case .chapter(let id): return "第\(id)章"
        case .wrongOnly: return "間違えた問題"
        }
    }
}

/// 参考書から「確認問題を解く」を押したときなどの出題リクエスト
struct DrillRequest: Equatable {
    var scope: DrillScope = .all
    var token = UUID()
}

struct DrillView: View {
    @Environment(ProgressStore.self) private var store
    @Binding var request: DrillRequest
    let openChapter: (Int) -> Void

    @State private var deck: [Question] = []
    @State private var index = 0
    @State private var choice: Int?
    @State private var sessionCorrect = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    scopeChips
                    if deck.isEmpty {
                        emptyState
                    } else if index >= deck.count {
                        resultCard
                    } else {
                        QuestionCard(question: deck[index],
                                     number: index + 1,
                                     total: deck.count,
                                     choice: $choice,
                                     onAnswer: answer,
                                     onNext: next,
                                     openChapter: openChapter)
                            .id(deck[index].id)
                    }
                }
                .padding(16)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("ドリル")
        }
        .onAppear { if deck.isEmpty { rebuild() } }
        .onChange(of: request) { rebuild() }
    }

    // MARK: - 出題範囲

    private var scopes: [DrillScope] {
        var list: [DrillScope] = [.all] + Content.categories.map { .category($0) } + [.wrongOnly]
        if case .chapter = request.scope { list.insert(request.scope, at: 0) }
        return list
    }

    private var scopeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(scopes, id: \.self) { s in
                    let selected = s == request.scope
                    Button {
                        request = DrillRequest(scope: s)
                    } label: {
                        Text(s.title)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selected ? Palette.accent.opacity(0.15) : Color.clear, in: Capsule())
                            .overlay(Capsule().stroke(selected ? Palette.accent : Color.secondary.opacity(0.35)))
                            .foregroundStyle(selected ? Palette.accent : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func rebuild() {
        let qs: [Question]
        switch request.scope {
        case .all: qs = Content.questions
        case .category(let c): qs = Content.questions.filter { $0.cat == c }
        case .chapter(let id): qs = Content.questions.filter { $0.chapter == id }
        case .wrongOnly: qs = Content.questions.filter { store.answers[$0.id]?.correct == false }
        }
        deck = qs.shuffled()
        index = 0
        choice = nil
        sessionCorrect = 0
    }

    private func answer(_ i: Int) {
        guard choice == nil else { return }
        choice = i
        let q = deck[index]
        store.record(question: q, choice: i)
        if i == q.a { sessionCorrect += 1 }
    }

    private func next() {
        choice = nil
        index += 1
    }

    // MARK: - 状態表示

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal").font(.largeTitle).foregroundStyle(Palette.ok)
            Text(request.scope == .wrongOnly ? "間違えた問題はありません" : "この範囲の問題はありません")
                .font(.headline)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var resultCard: some View {
        VStack(spacing: 14) {
            ProgressRing(value: Double(sessionCorrect) / Double(max(deck.count, 1)), lineWidth: 12)
                .frame(width: 110, height: 110)
            Text("\(deck.count)問中 \(sessionCorrect)問 正解").font(.title3.bold())
            if case .chapter(let id) = request.scope, let ch = Content.chapter(id) {
                Button("第\(id)章 \(ch.t) を読み直す") { openChapter(id) }
            }
            HStack {
                Button("もう一周") { rebuild() }
                    .buttonStyle(.borderedProminent)
                if sessionCorrect < deck.count {
                    Button("間違えた問題だけ") { request = DrillRequest(scope: .wrongOnly) }
                        .buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

// MARK: - 問題カード

private struct QuestionCard: View {
    let question: Question
    let number: Int
    let total: Int
    @Binding var choice: Int?
    let onAnswer: (Int) -> Void
    let onNext: () -> Void
    let openChapter: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text(question.cat).font(.caption.bold()).foregroundStyle(Palette.accent)
                if let since = question.since {
                    TagView(text: "since \(since)")
                }
                Spacer()
                Text("問 \(number) / \(total)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            Text(md(question.q)).font(.headline).fixedSize(horizontal: false, vertical: true)
            if let code = question.code {
                CodeBlockView(code: code)
            }
            VStack(spacing: 8) {
                ForEach(question.opts.indices, id: \.self) { i in
                    optionButton(i)
                }
            }
            if let choice {
                explanation(correct: choice == question.a)
            }
        }
        .padding(16)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.2)))
    }

    private func optionButton(_ i: Int) -> some View {
        let answered = choice != nil
        let isAnswer = i == question.a
        let isChosen = i == choice
        let tint: Color? = answered ? (isAnswer ? Palette.ok : (isChosen ? Palette.ng : nil)) : nil
        let letters = ["A", "B", "C", "D", "E"]

        return Button {
            onAnswer(i)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(letters[min(i, letters.count - 1)])
                    .font(.system(.subheadline, design: .monospaced).bold())
                    .foregroundStyle(.secondary)
                Text(md(question.opts[i]))
                    .font(.subheadline)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if answered && isAnswer {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.ok)
                } else if answered && isChosen {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.ng)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((tint ?? .clear).opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(tint ?? Color.secondary.opacity(0.3)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(answered)
    }

    private func explanation(correct: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Label(correct ? "正解" : "不正解", systemImage: correct ? "checkmark.circle" : "xmark.circle")
                .font(.headline)
                .foregroundStyle(correct ? Palette.ok : Palette.ng)
            Text(md(question.exp)).fixedSize(horizontal: false, vertical: true)
            HStack {
                if let ch = question.chapter, let chapter = Content.chapter(ch) {
                    Button {
                        openChapter(ch)
                    } label: {
                        Label("第\(ch)章 \(chapter.t)", systemImage: "book").font(.caption)
                    }
                }
                Spacer()
                Button(number < total ? "次の問題" : "結果を見る", action: onNext)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
