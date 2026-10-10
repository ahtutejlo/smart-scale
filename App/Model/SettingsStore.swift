import Foundation
import Observation

@Observable
@MainActor
final class SettingsStore {
    struct Settings: Codable, Equatable {
        var writesToHealth = true
        var hasImportedHealthHistory = false
        var selectedPersonID: UUID?
    }

    static let key = "profile.settings"

    var settings: Settings {
        didSet { save() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(Settings.self, from: $0) } ?? Settings()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Self.key)
        }
    }
}

extension SettingsStore.Settings {
    init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        writesToHealth = try container.decodeIfPresent(Bool.self, forKey: .writesToHealth) ?? writesToHealth
        hasImportedHealthHistory = try container.decodeIfPresent(Bool.self, forKey: .hasImportedHealthHistory) ?? hasImportedHealthHistory
        selectedPersonID = try container.decodeIfPresent(UUID.self, forKey: .selectedPersonID)
    }
}
