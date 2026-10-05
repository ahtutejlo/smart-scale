#if DEBUG
import Foundation
import ScaleKit
import SwiftData

@MainActor
enum DemoData {
    private static let suiteName = "smartscale.demo"

    static func freshDefaults() -> UserDefaults {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        return UserDefaults(suiteName: suiteName) ?? .standard
    }

    static func seed(into context: ModelContext, profile: ProfileStore) {
        profile.settings = ProfileStore.Settings(
            sex: .male,
            age: 36,
            heightCm: 180,
            goalWeightKg: 84,
            writesToHealth: false,
            hasImportedHealthHistory: true
        )
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        for daysAgo in stride(from: 90, through: 1, by: -1) where daysAgo % 5 != 2 {
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: today),
                  let date = calendar.date(byAdding: .minute, value: 7 * 60 + daysAgo % 40, to: day) else { continue }
            let x = Double(daysAgo)
            let weight = 88.0 + x * 0.045 + sin(x * 1.7) * 0.45 + sin(x * 0.53) * 0.3
            let reading = ScaleReading(
                date: date,
                weightKg: (weight * 10).rounded() / 10,
                impedanceOhm: 470 + x * 0.25 + sin(x * 0.9) * 8,
                algorithm: 0x07,
                heartRate: 72 + Int(sin(x) * 6),
                leftLegPercent: 50 + sin(x * 1.3) * 2
            )
            context.insert(Weighing(reading: reading, source: .scale))
        }
    }
}
#endif
