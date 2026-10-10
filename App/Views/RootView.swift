import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(WeighingRecorder.self) private var recorder

    var body: some View {
        TabView {
            Tab("Зважування", systemImage: "scalemass") {
                NavigationStack { WeighView() }
            }
            Tab("Тренди", systemImage: "chart.xyaxis.line") {
                NavigationStack { TrendsView() }
            }
            Tab("Аналіз", systemImage: "text.magnifyingglass") {
                NavigationStack { AnalysisView() }
            }
            Tab("Люди", systemImage: "person.2") {
                NavigationStack { PeopleView() }
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active:
                recorder.setForeground(true)
            case .background:
                recorder.setForeground(false)
            default:
                break
            }
        }
        .task {
            await recorder.importHealthHistoryOnce()
        }
    }
}
