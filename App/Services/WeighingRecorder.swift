import Foundation
import Observation
import ScaleKit
import SwiftData

@Observable
@MainActor
final class WeighingRecorder {
    let connection = ScaleConnection()
    private(set) var healthMessage: String?
    private(set) var isImporting = false

    private let store: WeighingStore
    private let health: HealthSync
    private let profile: ProfileStore

    init(context: ModelContext, health: HealthSync, profile: ProfileStore) {
        store = WeighingStore(context: context)
        self.health = health
        self.profile = profile
        connection.onEvent = { [weak self] event in
            switch event {
            case let .reading(reading):
                self?.record(reading, source: .scale)
            case let .storedReading(reading):
                self?.record(reading, source: .scaleMemory)
            default:
                break
            }
        }
    }

    func setForeground(_ isForeground: Bool) {
        guard isForeground, var userProfile = profile.userProfile else {
            connection.stop()
            return
        }
        if let latestKg = store.latest()?.weightKg {
            userProfile.initialWeightKg = latestKg
        }
        connection.start(profile: userProfile)
    }

    func importHealthHistoryOnce() async {
        guard !profile.settings.hasImportedHealthHistory else { return }
        profile.settings.hasImportedHealthHistory = true
        await importHealthHistory()
    }

    func importHealthHistory() async {
        guard health.isAvailable else {
            healthMessage = "Apple Health недоступний на цьому пристрої."
            return
        }
        isImporting = true
        defer { isImporting = false }
        do {
            let history = try await health.history()
            let added = store.insert(history.map { Weighing(imported: $0) })
            healthMessage = "Імпортовано \(added) з \(history.count) зважувань з Apple Health."
        } catch {
            healthMessage = "Не вдалося прочитати Apple Health: \(error.localizedDescription)"
        }
    }

    private func record(_ reading: ScaleReading, source: Weighing.Source) {
        let isNew = store.insert([Weighing(reading: reading, source: source)]) == 1
        guard isNew, profile.settings.writesToHealth, health.isAvailable else { return }
        let userProfile = profile.userProfile
        Task {
            do {
                try await health.save(reading, composition: reading.composition(for: userProfile), heightCm: userProfile?.heightCm)
            } catch {
                healthMessage = "Не вдалося записати в Apple Health: \(error.localizedDescription)"
            }
        }
    }
}
