import Foundation
import Observation
import ScaleKit

@Observable
@MainActor
final class ProfileStore {
    struct Settings: Codable, Equatable {
        var sex: UserProfile.Sex = .male
        var age: Int?
        var heightCm: Int?
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
        userProfile != nil
    }

    var userProfile: UserProfile? {
        guard let age = settings.age.positive, let heightCm = settings.heightCm.positive else { return nil }
        return UserProfile(
            heightCm: heightCm,
            age: age,
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

extension ProfileStore.Settings {
    init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sex = try container.decodeIfPresent(UserProfile.Sex.self, forKey: .sex) ?? sex
        age = try container.decodeIfPresent(Int.self, forKey: .age).positive
        heightCm = try container.decodeIfPresent(Int.self, forKey: .heightCm).positive
        goalWeightKg = try container.decodeIfPresent(Double.self, forKey: .goalWeightKg)
        writesToHealth = try container.decodeIfPresent(Bool.self, forKey: .writesToHealth) ?? writesToHealth
        hasImportedHealthHistory = try container.decodeIfPresent(Bool.self, forKey: .hasImportedHealthHistory) ?? hasImportedHealthHistory
    }
}

private extension Optional where Wrapped == Int {
    var positive: Int? {
        flatMap { $0 > 0 ? $0 : nil }
    }
}
