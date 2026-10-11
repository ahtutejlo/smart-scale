import Foundation
import Observation
import ScaleKit
import SwiftData

@Observable
@MainActor
final class WeighingRecorder {
    struct PendingAssignment {
        let weighing: Weighing
        let person: Person
        let usualKg: Double
    }

    let connection = ScaleConnection()
    private(set) var healthMessage: String?
    private(set) var isImporting = false
    private(set) var pendingAssignment: PendingAssignment?

    private let context: ModelContext
    private let store: WeighingStore
    private let health: HealthSync
    private let settings: SettingsStore

    init(context: ModelContext, health: HealthSync, settings: SettingsStore) {
        self.context = context
        store = WeighingStore(context: context)
        self.health = health
        self.settings = settings
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

    private var people: [Person] {
        (try? context.fetch(FetchDescriptor<Person>())) ?? []
    }

    func setForeground(_ isForeground: Bool) {
        guard isForeground else {
            connection.stop()
            return
        }
        let owner = people.owner
        var profile = owner?.userProfile ?? UserProfile(heightCm: 175, age: 30, sex: .male, initialWeightKg: 75)
        if let latestKg = owner?.latestWeightKg {
            profile.initialWeightKg = latestKg
        }
        connection.start(profile: profile)
    }

    func isJustFinished(_ weighing: Weighing) -> Bool {
        guard case let .finished(reading) = connection.state else { return false }
        return reading.date == weighing.date
    }

    func requestAssign(_ weighing: Weighing, to person: Person) {
        if let usualKg = person.usualWeightKg(near: weighing.date, excluding: weighing),
           !PersonMatcher.fits(weightKg: weighing.weightKg, usualKg: usualKg) {
            pendingAssignment = PendingAssignment(weighing: weighing, person: person, usualKg: usualKg)
        } else {
            assign(weighing, to: person)
        }
    }

    func confirmPendingAssignment() {
        guard let pending = pendingAssignment else { return }
        pendingAssignment = nil
        assign(pending.weighing, to: pending.person)
    }

    func cancelPendingAssignment() {
        pendingAssignment = nil
    }

    func discard(_ weighing: Weighing) {
        let previous = weighing.person
        weighing.person = nil
        ownershipChanged(weighing, from: previous)
        context.delete(weighing)
    }

    func importHealthHistoryOnce() async {
        guard !settings.settings.hasImportedHealthHistory else { return }
        settings.settings.hasImportedHealthHistory = true
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
            let owner = people.owner
            let added = store.insert(history.map { Weighing(imported: $0) })
            added.forEach { $0.person = owner }
            healthMessage = "Імпортовано \(added.count) з \(history.count) зважувань з Apple Health."
        } catch {
            healthMessage = "Не вдалося прочитати Apple Health: \(error.localizedDescription)"
        }
    }

    private func assign(_ weighing: Weighing, to person: Person) {
        let previous = weighing.person
        weighing.person = person
        ownershipChanged(weighing, from: previous)
    }

    private func record(_ reading: ScaleReading, source: Weighing.Source) {
        let matched = people.matching(weightKg: reading.weightKg)
        guard let weighing = store.insert([Weighing(reading: reading, source: source)]).first else { return }
        guard weighing.person == nil else { return }
        weighing.person = matched
        ownershipChanged(weighing, from: nil)
    }

    private func ownershipChanged(_ weighing: Weighing, from previous: Person?) {
        let wasOwners = previous?.isOwner == true
        let isOwners = weighing.person?.isOwner == true
        if isOwners, !wasOwners {
            saveToHealth(weighing)
        } else if wasOwners, !isOwners {
            removeFromHealth(weighing)
        }
    }

    private func saveToHealth(_ weighing: Weighing) {
        guard weighing.source != .appleHealth, settings.settings.writesToHealth, health.isAvailable else { return }
        let reading = weighing.reading
        let composition = weighing.composition
        let heightCm = weighing.person?.heightCm
        Task {
            do {
                try await health.save(reading, composition: composition, heightCm: heightCm)
            } catch {
                healthMessage = "Не вдалося записати в Apple Health: \(error.localizedDescription)"
            }
        }
    }

    private func removeFromHealth(_ weighing: Weighing) {
        guard weighing.source != .appleHealth, health.isAvailable else { return }
        let date = weighing.date
        Task {
            do {
                try await health.delete(at: date)
            } catch {
                healthMessage = "Не вдалося прибрати зважування з Apple Health: \(error.localizedDescription)"
            }
        }
    }
}
