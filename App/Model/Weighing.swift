import Foundation
import ScaleKit
import SwiftData

@Model
final class Weighing {
    #Index<Weighing>([\.date])

    enum Source: String, Codable {
        case scale
        case scaleMemory
        case appleHealth
    }

    var date: Date
    var weightKg: Double
    var impedanceOhm: Double?
    var algorithm: Int?
    var heartRate: Int?
    var leftLegPercent: Double?
    var importedBodyFatPercent: Double?
    var source: Source
    var person: Person?

    init(reading: ScaleReading, source: Source) {
        date = reading.date
        weightKg = reading.weightKg
        impedanceOhm = reading.impedanceOhm
        algorithm = reading.algorithm.map(Int.init)
        heartRate = reading.heartRate
        leftLegPercent = reading.leftLegPercent
        self.source = source
    }

    init(imported point: WeighingPoint) {
        date = point.date
        weightKg = point.weightKg
        importedBodyFatPercent = point.fatPercent
        source = .appleHealth
    }

    var reading: ScaleReading {
        ScaleReading(
            date: date,
            weightKg: weightKg,
            impedanceOhm: impedanceOhm,
            algorithm: algorithm.map { UInt8(clamping: $0) },
            heartRate: heartRate,
            leftLegPercent: leftLegPercent
        )
    }

    var composition: BodyComposition? {
        reading.composition(for: person?.userProfile)
    }

    var point: WeighingPoint {
        WeighingPoint(date: date, weightKg: weightKg, fatPercent: composition?.bodyFatPercent ?? importedBodyFatPercent)
    }
}

extension ScaleReading {
    func composition(for profile: UserProfile?) -> BodyComposition? {
        profile.flatMap { BodyComposition(reading: self, profile: $0) }
    }
}

extension Sequence where Element == Weighing {
    var points: [WeighingPoint] {
        map(\.point)
    }

    func belonging(to person: Person?) -> [Weighing] {
        filter { $0.person?.id == person?.id }
    }
}

extension FetchDescriptor where T == Weighing {
    static func newest(limit: Int) -> FetchDescriptor<Weighing> {
        var descriptor = FetchDescriptor<Weighing>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = limit
        return descriptor
    }
}
