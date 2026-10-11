import SwiftData
import SwiftUI

@main
struct SmartScaleApp: App {
    private let container: ModelContainer
    @State private var settings: SettingsStore
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
            container = try ModelContainer(for: Weighing.self, Person.self, configurations: ModelConfiguration(isStoredInMemoryOnly: isDemo))
        } catch {
            fatalError("Cannot open the weighings store: \(error)")
        }
        PeopleSetup.ensureOwner(in: container.mainContext, defaults: defaults)
        PeopleSetup.syncGoalStarts(in: container.mainContext)
        let settings = SettingsStore(defaults: defaults)
        self.container = container
        _settings = State(initialValue: settings)
        _recorder = State(initialValue: WeighingRecorder(context: container.mainContext, health: HealthSync(), settings: settings))
        #if DEBUG
        if isDemo {
            DemoData.seed(into: container.mainContext, settings: settings)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(recorder)
        }
        .modelContainer(container)
    }
}
