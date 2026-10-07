import SwiftUI

@main
struct JavaRestartApp: App {
    @State private var store = ProgressStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
    }
}

enum AppTab: Hashable {
    case book, drill, stats, build
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
            .tabItem { Label("参考書", systemImage: "book") }
            .tag(AppTab.book)

            DrillView(request: $drillRequest, openChapter: { id in
                bookPath = [id]
                tab = .book
            })
            .tabItem { Label("ドリル", systemImage: "checklist") }
            .tag(AppTab.drill)

            StatsView()
                .tabItem { Label("進捗", systemImage: "chart.bar.xaxis") }
                .tag(AppTab.stats)

            BuildView()
                .tabItem { Label("作って学ぶ", systemImage: "hammer") }
                .tag(AppTab.build)
        }
    }
}
