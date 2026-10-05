import Foundation
import HealthKit
import ScaleKit

final class HealthSync: Sendable {
    private let store = HKHealthStore()
    private let bodyMass = HKQuantityType(.bodyMass)
    private let bodyFat = HKQuantityType(.bodyFatPercentage)
    private let leanMass = HKQuantityType(.leanBodyMass)
    private let bodyMassIndex = HKQuantityType(.bodyMassIndex)
    private let kilograms = HKUnit.gramUnit(with: .kilo)

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func history() async throws -> [WeighingPoint] {
        try await requestAccess()
        let fromOtherApps = NSCompoundPredicate(notPredicateWithSubpredicate: HKQuery.predicateForObjects(from: HKSource.default()))
        let weights = try await samples(of: bodyMass, matching: fromOtherApps)
        let fatByMinute = Dictionary(
            try await samples(of: bodyFat, matching: fromOtherApps).map { (minute($0.startDate), $0.quantity.doubleValue(for: .percent()) * 100) },
            uniquingKeysWith: { first, _ in first }
        )
        return weights.map { sample in
            let key = minute(sample.startDate)
            return WeighingPoint(
                date: sample.startDate,
                weightKg: sample.quantity.doubleValue(for: kilograms),
                fatPercent: fatByMinute[key] ?? fatByMinute[key - 1] ?? fatByMinute[key + 1]
            )
        }
    }

    func save(_ reading: ScaleReading, composition: BodyComposition?, heightCm: Int?) async throws {
        try await requestAccess()
        let syncPrefix = "smartscale-\(Int(reading.date.timeIntervalSince1970))"
        func sample(_ type: HKQuantityType, _ unit: HKUnit, _ value: Double, _ suffix: String) -> HKQuantitySample {
            HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: unit, doubleValue: value),
                start: reading.date,
                end: reading.date,
                metadata: [HKMetadataKeySyncIdentifier: "\(syncPrefix)-\(suffix)", HKMetadataKeySyncVersion: 1]
            )
        }
        var samples = [sample(bodyMass, kilograms, reading.weightKg, "mass")]
        if let heightCm, heightCm > 0 {
            let heightM = Double(heightCm) / 100
            samples.append(sample(bodyMassIndex, .count(), reading.weightKg / (heightM * heightM), "bmi"))
        }
        if let composition {
            samples.append(sample(bodyFat, .percent(), composition.bodyFatPercent / 100, "fat"))
            samples.append(sample(leanMass, kilograms, composition.leanMassKg, "lean"))
        }
        try await store.save(samples)
    }

    private func requestAccess() async throws {
        try await store.requestAuthorization(toShare: [bodyMass, bodyFat, leanMass, bodyMassIndex], read: [bodyMass, bodyFat])
    }

    private func samples(of type: HKQuantityType, matching predicate: NSPredicate) async throws -> [HKQuantitySample] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return try await descriptor.result(for: store)
    }

    private func minute(_ date: Date) -> Int {
        Int(date.timeIntervalSince1970 / 60)
    }
}
