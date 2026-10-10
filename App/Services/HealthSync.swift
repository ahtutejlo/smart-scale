import Foundation
import HealthKit
import ScaleKit

final class HealthSync: Sendable {
    private enum Kind: String, CaseIterable {
        case mass
        case bmi
        case fat
        case lean

        var quantityType: HKQuantityType {
            switch self {
            case .mass: HKQuantityType(.bodyMass)
            case .bmi: HKQuantityType(.bodyMassIndex)
            case .fat: HKQuantityType(.bodyFatPercentage)
            case .lean: HKQuantityType(.leanBodyMass)
            }
        }
    }

    private let store = HKHealthStore()
    private let kilograms = HKUnit.gramUnit(with: .kilo)

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func history() async throws -> [WeighingPoint] {
        try await requestAccess()
        let fromOtherApps = NSCompoundPredicate(notPredicateWithSubpredicate: HKQuery.predicateForObjects(from: HKSource.default()))
        let weights = try await samples(of: Kind.mass.quantityType, matching: fromOtherApps)
        let fatByMinute = Dictionary(
            try await samples(of: Kind.fat.quantityType, matching: fromOtherApps).map { (minute($0.startDate), $0.quantity.doubleValue(for: .percent()) * 100) },
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
        func sample(_ kind: Kind, _ unit: HKUnit, _ value: Double) -> HKQuantitySample {
            HKQuantitySample(
                type: kind.quantityType,
                quantity: HKQuantity(unit: unit, doubleValue: value),
                start: reading.date,
                end: reading.date,
                metadata: [HKMetadataKeySyncIdentifier: syncIdentifier(reading.date, kind), HKMetadataKeySyncVersion: 1]
            )
        }
        var samples = [sample(.mass, kilograms, reading.weightKg)]
        if let heightCm, heightCm > 0 {
            let heightM = Double(heightCm) / 100
            samples.append(sample(.bmi, .count(), reading.weightKg / (heightM * heightM)))
        }
        if let composition {
            samples.append(sample(.fat, .percent(), composition.bodyFatPercent / 100))
            samples.append(sample(.lean, kilograms, composition.leanMassKg))
        }
        try await store.save(samples)
    }

    func delete(at date: Date) async throws {
        try await requestAccess()
        for kind in Kind.allCases {
            let predicate = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: [syncIdentifier(date, kind)])
            _ = try await store.deleteObjects(of: kind.quantityType, predicate: predicate)
        }
    }

    private func requestAccess() async throws {
        try await store.requestAuthorization(
            toShare: Set(Kind.allCases.map(\.quantityType)),
            read: [Kind.mass.quantityType, Kind.fat.quantityType]
        )
    }

    private func samples(of type: HKQuantityType, matching predicate: NSPredicate) async throws -> [HKQuantitySample] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return try await descriptor.result(for: store)
    }

    private func syncIdentifier(_ date: Date, _ kind: Kind) -> String {
        "smartscale-\(Int(date.timeIntervalSince1970))-\(kind.rawValue)"
    }

    private func minute(_ date: Date) -> Int {
        Int(date.timeIntervalSince1970 / 60)
    }
}
