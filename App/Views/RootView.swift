import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(WeighingRecorder.self) private var recorder

    var body: some View {
        TabView {
            Tab("Сьогодні", systemImage: "sun.max") {
                NavigationStack { TodayView() }
            }
            Tab("Історія", systemImage: "chart.xyaxis.line") {
                NavigationStack { HistoryView() }
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
        .confirmsUnusualAssignment(recorder)
        .task {
            await recorder.importHealthHistoryOnce()
        }
    }
}
