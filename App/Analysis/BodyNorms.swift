import ScaleKit

struct Norm: Sendable {
    enum Tone: Sendable {
        case good
        case warning
        case neutral
    }

    let label: String
    let tone: Tone

    static let below = Norm(label: "нижче норми", tone: .warning)
    static let normal = Norm(label: "норма", tone: .good)
    static let above = Norm(label: "вище норми", tone: .warning)
    static let farAbove = Norm(label: "значно вище норми", tone: .warning)
}

enum BodyNorms {
    static func bodyFat(_ percent: Double, age: Int, sex: UserProfile.Sex) -> Norm {
        let (normal, farAboveFrom): (Range<Double>, Double) = switch (sex, age) {
        case (.male, ..<40): (8..<20, 25)
        case (.male, ..<60): (11..<22, 28)
        case (.male, _): (13..<25, 30)
        case (.female, ..<40): (21..<33, 39)
        case (.female, ..<60): (23..<34, 40)
        case (.female, _): (24..<36, 42)
        }
        return grade(percent, normal: normal, farAboveFrom: farAboveFrom)
    }

    static func visceralFat(_ level: Double) -> Norm {
        grade(level, normal: 0..<10, farAboveFrom: 15)
    }

    static func water(_ percent: Double, sex: UserProfile.Sex) -> Norm {
        grade(percent, normal: sex == .male ? 50..<66 : 45..<61)
    }

    static func heartRate(_ bpm: Int) -> Norm {
        bpm < 60 ? Norm(label: "низький", tone: .neutral) : grade(Double(bpm), normal: 60..<101)
    }

    private static func grade(_ value: Double, normal: Range<Double>, farAboveFrom: Double = .infinity) -> Norm {
        if value < normal.lowerBound { return .below }
        if value < normal.upperBound { return .normal }
        return value < farAboveFrom ? .above : .farAbove
    }
}
