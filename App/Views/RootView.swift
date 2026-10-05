import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(WeighingRecorder.self) private var recorder
    @Environment(ProfileStore.self) private var profile

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
            Tab("Профіль", systemImage: "person.crop.circle") {
                NavigationStack { ProfileView() }
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
        .onChange(of: profile.userProfile) {
            recorder.setForeground(scenePhase != .background)
        }
        .task {
            await recorder.importHealthHistoryOnce()
        }
    }
}
