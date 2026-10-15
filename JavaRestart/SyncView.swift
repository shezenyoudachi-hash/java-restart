import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 進捗画面の「ほかの iPhone と同期」欄
struct SyncCard: View {
    @Environment(SyncService.self) private var sync

    @State private var exportFile: ExportedFile?
    @State private var importing = false
    @State private var resultMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ほかの iPhone と同期").font(.headline)

            // A. 書き出し・読み込み
            VStack(alignment: .leading, spacing: 8) {
                Label("ファイルで受け渡す", systemImage: "arrow.left.arrow.right")
                    .font(.subheadline.weight(.semibold))
                Text("進捗を書き出して AirDrop でもう一方の iPhone に送り、そちらで「読み込む」を選びます。上書きではなく合わせるので、どちらで読んだ章もマークも消えません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button {
                        do {
                            exportFile = ExportedFile(url: try sync.exportFile())
                        } catch {
                            errorMessage = "書き出せませんでした：\(error.localizedDescription)"
                        }
                    } label: {
                        Label("進捗を書き出す", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        importing = true
                    } label: {
                        Label("読み込む", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                Text("AirDrop で受け取ったファイルは「ファイル」アプリの「ダウンロード」に保存し、「読み込む」から選んでください。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            // B. iCloud 自動同期
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: Binding(get: { sync.cloudState == .on }, set: { sync.setCloud($0) })) {
                    Label("iCloud で自動同期", systemImage: "icloud")
                        .font(.subheadline.weight(.semibold))
                }
                cloudStatus
            }
        }
        .sheet(item: $exportFile) { file in
            ActivityView(items: [file.url])
                .presentationDetents([.medium, .large])
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                do {
                    resultMessage = try sync.importFile(at: url).message
                } catch {
                    errorMessage = error.localizedDescription
                }
            case .failure(let error):
                errorMessage = "ファイルを開けませんでした：\(error.localizedDescription)"
            }
        }
        .alert("読み込みました", isPresented: Binding(get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } })) {
            Button("OK") { resultMessage = nil }
        } message: {
            Text(resultMessage ?? "")
        }
        .alert("うまくいきませんでした", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var cloudStatus: some View {
        switch sync.cloudState {
        case .off:
            Text("オンにすると、同じ Apple アカウントの iPhone どうしで自動的に同期します（有料の開発者登録が必要です）。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .on:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.icloud").foregroundStyle(Palette.ok)
                if let last = sync.lastCloudSync {
                    Text("同期中・最終同期 \(last.formatted(date: .omitted, time: .shortened))")
                } else {
                    Text("同期中")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        case .unavailable(let reason):
            Label(reason, systemImage: "exclamationmark.icloud")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 共有シート（AirDrop など）
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// 書き出したファイル（共有シートに渡す）
struct ExportedFile: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
