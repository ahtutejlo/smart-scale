import SwiftData
import SwiftUI

@main
struct SmartScaleApp: App {
    private let container: ModelContainer
    @State private var profile: ProfileStore
    @State private var recorder: WeighingRecorder

    init() {
        #if DEBUG
        let isDemo = ProcessInfo.processInfo.arguments.contains("-demo")
        let defaults = isDemo ? DemoData.freshDefaults() : .standard
        #else
        let isDemo = false
        let defaults = UserDefaults.standard
        #endif
        let container: ModelContainer
        do {
            container = try ModelContainer(for: Weighing.self, configurations: ModelConfiguration(isStoredInMemoryOnly: isDemo))
        } catch {
            fatalError("Cannot open the weighings store: \(error)")
        }
        let profile = ProfileStore(defaults: defaults)
        self.container = container
        _profile = State(initialValue: profile)
        _recorder = State(initialValue: WeighingRecorder(context: container.mainContext, health: HealthSync(), profile: profile))
        #if DEBUG
        if isDemo {
            DemoData.seed(into: container.mainContext, profile: profile)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(profile)
                .environment(recorder)
        }
        .modelContainer(container)
    }
}
