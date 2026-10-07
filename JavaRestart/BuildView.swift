import SwiftUI

struct BuildView: View {
    @Environment(ProgressStore.self) private var store

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("題材：原料受入・試験管理（ミニ版）").font(.headline)
                        Text("原料ロットを受け入れ、試験結果を登録し、承認して使用可にするまでを小さなJavaアプリで作ります。CLIから始めて、DB・テスト・Spring Bootへと段階的に育てます。")
                            .font(.subheadline).foregroundStyle(.secondary)
                        ProgressView(value: Double(store.stepsDone.count), total: Double(Content.steps.count)) {
                            Text("\(store.stepsDone.count) / \(Content.steps.count) ステップ完了")
                                .font(.caption).monospacedDigit()
                        }
                    }
                    .padding(.vertical, 4)
                }
                ForEach(Content.steps) { step in
                    Section {
                        StepRow(step: step)
                    }
                }
            }
            .navigationTitle("作って学ぶ")
        }
    }
}

private struct StepRow: View {
    @Environment(ProgressStore.self) private var store
    let step: BuildStep

    var body: some View {
        let done = store.stepsDone.contains(step.id)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    store.toggleStep(step.id)
                } label: {
                    Image(systemName: done ? "checkmark.circle.fill" : "\(step.id + 1).circle")
                        .font(.title2)
                        .foregroundStyle(Palette.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(done ? "ステップ\(step.id + 1)を未完了に戻す" : "ステップ\(step.id + 1)を完了にする")

                VStack(alignment: .leading, spacing: 6) {
                    Text(step.t).font(.headline)
                        .strikethrough(done, color: .secondary)
                    FlowLayout(spacing: 6).callAsFunction {
                        ForEach(step.learn, id: \.self) { TagView(text: $0) }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(step.tasks, id: \.self) { task in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(Palette.accent)
                        Text(md(task)).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let code = step.code {
                DisclosureGroup("出発点のコード") {
                    CodeBlockView(code: code).padding(.top, 6)
                }
                .font(.subheadline)
            }
        }
        .padding(.vertical, 6)
    }
}
