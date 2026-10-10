import Foundation
import ScaleKit
import SwiftData

@MainActor
enum PeopleSetup {
    private struct LegacyProfile: Decodable {
        let sex: UserProfile.Sex?
        let age: Int?
        let heightCm: Int?
        let goalWeightKg: Double?
    }

    static func ensureOwner(in context: ModelContext, defaults: UserDefaults) {
        guard (try? context.fetchCount(FetchDescriptor<Person>())) == 0 else { return }
        let legacy = defaults.data(forKey: SettingsStore.key).flatMap { try? JSONDecoder().decode(LegacyProfile.self, from: $0) }
        let owner = Person(
            name: "Я",
            sex: legacy?.sex ?? .male,
            age: legacy?.age.positive,
            heightCm: legacy?.heightCm.positive,
            goalWeightKg: legacy?.goalWeightKg,
            isOwner: true
        )
        context.insert(owner)
        let unassigned = FetchDescriptor<Weighing>(predicate: #Predicate { $0.person == nil })
        for weighing in (try? context.fetch(unassigned)) ?? [] {
            weighing.person = owner
        }
    }
}
