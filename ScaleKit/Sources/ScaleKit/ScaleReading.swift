import Foundation

public struct ScaleReading: Codable, Equatable, Sendable {
    public var date: Date
    public var weightKg: Double
    public var impedanceOhm: Double?
    public var algorithm: UInt8?
    public var heartRate: Int?
    public var leftLegPercent: Double?

    public init(
        date: Date,
        weightKg: Double,
        impedanceOhm: Double? = nil,
        algorithm: UInt8? = nil,
        heartRate: Int? = nil,
        leftLegPercent: Double? = nil
    ) {
        self.date = date
        self.weightKg = weightKg
        self.impedanceOhm = impedanceOhm
        self.algorithm = algorithm
        self.heartRate = heartRate
        self.leftLegPercent = leftLegPercent
    }
}

extension ScaleReading {
    public init(_ stored: StoredMeasurement) {
        self.init(
            date: stored.date,
            weightKg: stored.weightKg,
            impedanceOhm: ActiveEraProtocol.impedanceOhm(raw: stored.rawImpedance, weightKg: stored.weightKg),
            algorithm: stored.algorithm,
            heartRate: stored.heartRate,
            leftLegPercent: stored.weightKg > 0 ? stored.leftLegKg / stored.weightKg * 100 : nil
        )
    }
}

public struct MeasurementSession: Sendable {
    public private(set) var liveWeightKg: Double?
    public private(set) var isFinished = false
    private var stableWeightKg: Double?
    private var expectsHeartRate = false
    private var impedance: (raw: Int, algorithm: UInt8)?
    private var heartRate: Int?
    private var leftLegPercent: Double?

    public init() {}

    private var isComplete: Bool {
        stableWeightKg != nil && impedance != nil && (!expectsHeartRate || heartRate != nil)
    }

    public mutating func consume(_ packet: ScalePacket) -> Duration? {
        guard !isFinished else { return nil }
        let wasComplete = isComplete
        switch packet {
        case let .liveWeight(kg, isStable, reportsHeartRate):
            liveWeightKg = kg
            expectsHeartRate = reportsHeartRate
            if isStable, stableWeightKg == nil {
                stableWeightKg = kg
            }
        case let .balance(leftPercent, _, isFinal):
            if isFinal {
                leftLegPercent = leftPercent
            }
        case let .impedance(raw, algorithm):
            impedance = (raw, algorithm)
        case let .heartRate(bpm):
            heartRate = bpm
        case .stored, .unknown:
            break
        }
        guard stableWeightKg != nil else { return nil }
        if !isComplete {
            return .seconds(6)
        }
        return wasComplete ? nil : .milliseconds(1500)
    }

    public mutating func finish(at date: Date) -> ScaleReading? {
        guard !isFinished, let weight = stableWeightKg else { return nil }
        isFinished = true
        return ScaleReading(
            date: date,
            weightKg: weight,
            impedanceOhm: impedance.map { ActiveEraProtocol.impedanceOhm(raw: $0.raw, weightKg: weight) },
            algorithm: impedance?.algorithm,
            heartRate: heartRate,
            leftLegPercent: leftLegPercent
        )
    }
}
