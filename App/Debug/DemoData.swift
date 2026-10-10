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

    static func seed(into context: ModelContext, settings: SettingsStore) {
        settings.settings = SettingsStore.Settings(writesToHealth: false, hasImportedHealthHistory: true)
        guard let owner = (try? context.fetch(FetchDescriptor<Person>()))?.owner else { return }
        owner.name = "Андрій"
        owner.age = 36
        owner.heightCm = 180
        owner.goalWeightKg = 84
        let partner = Person(name: "Марія", sex: .female, age: 31, heightCm: 165, goalWeightKg: 58)
        context.insert(partner)

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        for daysAgo in stride(from: 90, through: 1, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
            let x = Double(daysAgo)
            if daysAgo % 5 != 2, let date = calendar.date(byAdding: .minute, value: 7 * 60 + daysAgo % 40, to: day) {
                let weight = 88.0 + x * 0.045 + sin(x * 1.7) * 0.45 + sin(x * 0.53) * 0.3
                insert(weight: weight, impedance: 470 + x * 0.25 + sin(x * 0.9) * 8, date: date, person: owner, into: context)
            }
            if daysAgo % 3 == 0, let date = calendar.date(byAdding: .minute, value: 8 * 60 + daysAgo % 30, to: day) {
                let weight = 61.0 + x * 0.02 + sin(x * 1.3) * 0.35
                insert(weight: weight, impedance: 590 + sin(x * 0.7) * 10, date: date, person: partner, into: context)
            }
        }
        insert(weight: 74.3, impedance: 520, date: .now.addingTimeInterval(-3600), person: nil, into: context)
    }

    private static func insert(weight: Double, impedance: Double, date: Date, person: Person?, into context: ModelContext) {
        let reading = ScaleReading(
            date: date,
            weightKg: (weight * 10).rounded() / 10,
            impedanceOhm: impedance,
            algorithm: 0x07,
            heartRate: 70 + Int(date.timeIntervalSince1970.truncatingRemainder(dividingBy: 12)),
            leftLegPercent: 49 + date.timeIntervalSince1970.truncatingRemainder(dividingBy: 3)
        )
        let weighing = Weighing(reading: reading, source: .scale)
        weighing.person = person
        context.insert(weighing)
    }
}
#endif
