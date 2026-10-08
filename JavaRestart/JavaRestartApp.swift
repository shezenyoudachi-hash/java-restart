import SwiftUI

@main
struct JavaRestartApp: App {
    @State private var store = ProgressStore()
    @State private var player = SpeechPlayer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(player)
                .onAppear {
                    player.onFinishNote = { [store] note in store.markListened(note.id) }
                }
        }
    }
}

enum AppTab: Hashable {
    case book, notes, drill, stats, build
}

struct RootView: View {
    @State private var tab: AppTab = .book
    @State private var bookPath: [Int] = []
    @State private var drillRequest = DrillRequest()

    var body: some View {
        TabView(selection: $tab) {
            BookView(path: $bookPath, openQuiz: { chapter in
                drillRequest = DrillRequest(scope: .chapter(chapter.id))
                tab = .drill
            })
            .miniPlayer()
            .tabItem { Label("参考書", systemImage: "book") }
            .tag(AppTab.book)

            NotesView(openChapter: openChapter)
                .miniPlayer()
                .tabItem { Label("ノート", systemImage: "headphones") }
                .tag(AppTab.notes)

            DrillView(request: $drillRequest, openChapter: openChapter)
                .miniPlayer()
                .tabItem { Label("ドリル", systemImage: "checklist") }
                .tag(AppTab.drill)

            StatsView()
                .miniPlayer()
                .tabItem { Label("進捗", systemImage: "chart.bar.xaxis") }
                .tag(AppTab.stats)

            BuildView()
                .miniPlayer()
                .tabItem { Label("作って学ぶ", systemImage: "hammer") }
                .tag(AppTab.build)
        }
    }

    private func openChapter(_ id: Int) {
        bookPath = [id]
        tab = .book
    }
}
