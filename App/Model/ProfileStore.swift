import Foundation
import Observation
import ScaleKit

@Observable
@MainActor
final class ProfileStore {
    struct Settings: Codable, Equatable {
        var sex: UserProfile.Sex = .male
        var age = 0
        var heightCm = 0
        var goalWeightKg: Double?
        var writesToHealth = true
        var hasImportedHealthHistory = false
    }

    var settings: Settings {
        didSet { save() }
    }

    private let defaults: UserDefaults
    private static let key = "profile.settings"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(Settings.self, from: $0) } ?? Settings()
    }

    var isComplete: Bool {
        settings.age > 0 && settings.heightCm > 0
    }

    var userProfile: UserProfile? {
        guard isComplete else { return nil }
        return UserProfile(
            heightCm: settings.heightCm,
            age: settings.age,
            sex: settings.sex,
            initialWeightKg: settings.goalWeightKg ?? 75,
            goalWeightKg: settings.goalWeightKg
        )
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
