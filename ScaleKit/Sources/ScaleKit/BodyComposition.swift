import Foundation

public struct BodyComposition: Equatable, Sendable {
    public var bodyFatPercent: Double
    public var leanMassKg: Double
    public var musclePercent: Double?
    public var skeletalMusclePercent: Double?
    public var waterPercent: Double?
    public var proteinPercent: Double?
    public var boneMassKg: Double?
    public var visceralFat: Double?
    public var bmrKcal: Int?
    public var metabolicAge: Int?
}

extension BodyComposition {
    public init?(reading: ScaleReading, profile: UserProfile) {
        guard let impedance = reading.impedanceOhm, impedance > 10 else { return nil }
        let input = BIAInput(
            weight: reading.weightKg,
            height: Double(profile.heightCm),
            age: Double(profile.age),
            impedance: impedance,
            isMale: profile.sex == .male
        )
        self = reading.algorithm == 0x07 ? WLA07(input).composition : Self.estimate(input)
    }

    private static func estimate(_ input: BIAInput) -> BodyComposition {
        let fatFreeMass = 0.36 * (input.height * input.height / input.impedance)
            + 0.162 * input.height
            + 0.289 * input.weight
            - 0.134 * input.age
            + 4.83 * (input.isMale ? 1 : 0)
            - 6.83
        let fatPercent = max(input.weight - fatFreeMass, 0) / input.weight * 100
        return BodyComposition(bodyFatPercent: fatPercent, leanMassKg: input.leanMass(fatPercent: fatPercent))
    }
}

private struct BIAInput {
    let weight: Double
    let height: Double
    let age: Double
    let impedance: Double
    let isMale: Bool

    func leanMass(fatPercent: Double) -> Double {
        weight * (100 - fatPercent) / 100
    }
}

private struct WLA07 {
    private enum Metric: Int {
        case bodyFat = 0
        case muscle = 2
        case water = 4
        case bmr = 6
        case visceralFat = 8
        case metabolicAge = 10
    }

    private struct Coefficients {
        let height: Double
        let weight: Double
        let age: Double
        let impedance: Double
        let constant: Double
    }

    private static let table: [Coefficients] = [
        Coefficients(height: -3332, weight: 7509, age: 196, impedance: 72, constant: 227193),
        Coefficients(height: -3315, weight: 6216, age: 183, impedance: 85, constant: 225540),
        Coefficients(height: 31860, weight: 19340, age: -2060, impedance: -1320, constant: -1645560),
        Coefficients(height: 28670, weight: 38940, age: -4080, impedance: -1235, constant: -1576650),
        Coefficients(height: 87700, weight: 297300, age: 12800, impedance: -6030, constant: 517500),
        Coefficients(height: 93900, weight: 375800, age: -3200, impedance: -6925, constant: 97000),
        Coefficients(height: 75432, weight: 99474, age: -34382, impedance: -3090, constant: -2882821),
        Coefficients(height: 75037, weight: 131523, age: -43376, impedance: -3486, constant: -3117751),
        Coefficients(height: -1651, weight: 2628, age: 649, impedance: 24, constant: 123445),
        Coefficients(height: -2675, weight: 4200, age: 1462, impedance: 123, constant: 139871),
        Coefficients(height: -11165, weight: 15784, age: 4615, impedance: 415, constant: 832548),
        Coefficients(height: -7471, weight: 9161, age: 4184, impedance: 517, constant: 542267),
    ]

    private let input: BIAInput
    private let bodyFatRaw: Double
    private let muscleKg: Double
    private let musclePercentRaw: Double
    private let waterRaw: Double

    init(_ input: BIAInput) {
        self.input = input
        bodyFatRaw = Self.clamp(Self.regress(.bodyFat, input) / input.weight * 100, 5, 45)

        let muscleRegression = Self.regress(.muscle, input) / 10
        let residual = input.weight * (1 - bodyFatRaw / 100) - muscleRegression
        if residual >= 4 {
            muscleKg = muscleRegression + residual - 4
        } else if residual > 1 {
            muscleKg = muscleRegression
        } else {
            muscleKg = muscleRegression + residual - 1
        }
        musclePercentRaw = muscleKg / input.weight * 100
        waterRaw = Self.regress(.water, input) / input.weight
    }

    var composition: BodyComposition {
        let bodyFatPercent = Self.roundToTenth(bodyFatRaw)
        return BodyComposition(
            bodyFatPercent: bodyFatPercent,
            leanMassKg: input.leanMass(fatPercent: bodyFatPercent),
            musclePercent: Self.roundToTenth(musclePercentRaw),
            skeletalMusclePercent: skeletalMusclePercent,
            waterPercent: waterPercent,
            proteinPercent: Self.roundToTenth(Self.clamp(musclePercentRaw - Self.clamp(waterRaw, 20, 85), 5, 32)),
            boneMassKg: Self.roundToTenth(Self.clamp(input.weight - bodyFatRaw * input.weight / 100 - muscleKg, 1, 4)),
            visceralFat: visceralFat,
            bmrKcal: Int(Self.clamp(Self.regress(.bmr, input), 400, 3500).rounded()),
            metabolicAge: metabolicAge
        )
    }

    private var waterPercent: Double {
        let residual = musclePercentRaw - waterRaw
        let corrected: Double
        if residual >= 32 {
            corrected = musclePercentRaw - 32
        } else if residual > 5 {
            corrected = waterRaw
        } else {
            corrected = musclePercentRaw - 5
        }
        return Self.roundToTenth(Self.clamp(corrected, 20, 85))
    }

    private var visceralFat: Double {
        let truncated = Int(Self.regress(.visceralFat, input) * 10)
        let base = truncated / 10 * 10
        let rounded = truncated % 10 < 6 ? base : base + 5
        return Self.roundToTenth(Self.clamp(Double(rounded) / 10, 1, 59))
    }

    private var metabolicAge: Int {
        guard input.age > 14 else { return Int(input.age) }
        return max(Int(min(Self.regress(.metabolicAge, input), 80)), 15)
    }

    private var skeletalMusclePercent: Double {
        let estimate = input.impedance * -0.017
            + input.weight * 0.1745
            + input.height * 0.2573
            + (input.isMale ? 2.4269 : 0)
            - input.age * 0.0161
            - 20.2165
        let skeletal = Self.clamp(estimate, muscleKg * 0.45, muscleKg * 0.7)
        return Self.roundToTenth(skeletal / input.weight * 100)
    }

    private static func regress(_ metric: Metric, _ input: BIAInput) -> Double {
        let c = table[metric.rawValue + (input.isMale ? 1 : 0)]
        return (input.height * c.height + input.weight * c.weight + input.age * c.age + input.impedance * c.impedance + c.constant) / 10000
    }

    private static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(max(value, lower), upper)
    }

    // Mirrors the vendor app's rounding so values match what Active Era shows.
    private static func roundToTenth(_ value: Double) -> Double {
        var tenths = value.truncatingRemainder(dividingBy: 1) * 10
        tenths = tenths.truncatingRemainder(dividingBy: 1) > 0.5 ? tenths.rounded(.up) : tenths.rounded(.down)
        return Double(Int(value)) + tenths / 10
    }
}
