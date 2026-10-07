import SwiftUI

struct StatsView: View {
    @Environment(ProgressStore.self) private var store
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    overview
                    card("学習カレンダー（12週間）") { ActivityHeatmap() }
                    card("参考書：部ごとの読了") { partBars }
                    card("ドリル：カテゴリ別の正解数") { categoryBars }
                    card("作って学ぶ") {
                        bar(label: "完了したステップ",
                            done: store.stepsDone.count,
                            total: Content.steps.count)
                    }
                    Button("進捗をすべてリセット", role: .destructive) { confirmReset = true }
                        .font(.footnote)
                        .padding(.top, 8)
                }
                .padding(16)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("進捗")
            .confirmationDialog("読了状況・回答履歴・学習カレンダーをすべて消去します。元に戻せません。",
                                isPresented: $confirmReset, titleVisibility: .visible) {
                Button("リセットする", role: .destructive) { store.resetAll() }
            }
        }
    }

    private var overview: some View {
        let answered = store.answers.count
        let accuracy = answered == 0 ? 0 : Double(store.answers.values.filter(\.correct).count) / Double(answered)
        return HStack(spacing: 20) {
            ProgressRing(value: store.bookRatio, lineWidth: 12)
                .frame(width: 110, height: 110)
            VStack(alignment: .leading, spacing: 10) {
                metric("読了", "\(store.doneChapterCount) / \(Content.chapters.count) 章")
                metric("正答率", answered == 0 ? "—" : "\(Int((accuracy * 100).rounded()))%（\(answered)問回答）")
                metric("連続学習", "\(store.streak) 日")
                metric("学習した日", "\(store.studyDayCount) 日")
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
    }

    private var partBars: some View {
        VStack(spacing: 12) {
            ForEach(Content.parts) { p in
                bar(label: "第\(p.n)部 \(p.t)",
                    done: store.doneCount(in: p),
                    total: Content.chapters(in: p).count)
            }
        }
    }

    private var categoryBars: some View {
        VStack(spacing: 12) {
            ForEach(Content.categories, id: \.self) { c in
                let qs = Content.questions.filter { $0.cat == c }
                bar(label: c, done: store.correctCount(qs), total: qs.count)
            }
        }
    }

    private func bar(label: String, done: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.subheadline)
                Spacer()
                Text("\(done) / \(total)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            ProgressView(value: Double(done), total: Double(max(total, 1)))
        }
    }

    private func card<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

/// 直近12週間の学習量を、1日1マスで表示する
struct ActivityHeatmap: View {
    @Environment(ProgressStore.self) private var store
    private let weekCount = 12

    var body: some View {
        let weeks = makeWeeks()
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 4) {
                VStack(spacing: 4) {
                    ForEach(weekdayLabels.indices, id: \.self) { i in
                        Text(weekdayLabels[i])
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .frame(width: 14, height: 14)
                    }
                }
                ForEach(weeks.indices, id: \.self) { w in
                    VStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { d in
                            cell(weeks[w][d])
                        }
                    }
                }
            }
            HStack(spacing: 4) {
                Text("少").font(.caption2).foregroundStyle(.secondary)
                ForEach([0, 1, 3, 6], id: \.self) { n in
                    RoundedRectangle(cornerRadius: 3).fill(color(for: n)).frame(width: 12, height: 12)
                }
                Text("多").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var weekdayLabels: [String] {
        let symbols = Calendar.current.veryShortWeekdaySymbols   // 日〜土
        let first = Calendar.current.firstWeekday - 1
        return (0..<7).map { symbols[(first + $0) % 7] }
    }

    private func cell(_ date: Date?) -> some View {
        let n = date.map { store.activityCount(on: $0) } ?? 0
        return RoundedRectangle(cornerRadius: 3)
            .fill(date == nil ? Color.clear : color(for: n))
            .frame(width: 14, height: 14)
    }

    private func color(for n: Int) -> Color {
        switch n {
        case 0: return Color.secondary.opacity(0.15)
        case 1...2: return Palette.accent.opacity(0.35)
        case 3...5: return Palette.accent.opacity(0.65)
        default: return Palette.accent
        }
    }

    private func makeWeeks() -> [[Date?]] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today)
        let offset = (weekday - cal.firstWeekday + 7) % 7
        guard let thisWeek = cal.date(byAdding: .day, value: -offset, to: today),
              let start = cal.date(byAdding: .day, value: -7 * (weekCount - 1), to: thisWeek) else { return [] }
        return (0..<weekCount).map { w in
            (0..<7).map { d -> Date? in
                guard let day = cal.date(byAdding: .day, value: w * 7 + d, to: start), day <= today else { return nil }
                return day
            }
        }
    }
}
