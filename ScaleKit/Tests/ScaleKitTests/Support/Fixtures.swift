import Foundation
@testable import ScaleKit

enum FixtureError: Error, CustomStringConvertible {
    case missing(String)
    case invalidHex(String)
    case notAScalePacket(String)

    var description: String {
        switch self {
        case let .missing(name): "fixture \(name).jsonl is not in the test bundle"
        case let .invalidHex(hex): "not a hex byte string: \(hex)"
        case let .notAScalePacket(hex): "captured packet does not decode: \(hex)"
        }
    }
}

enum Capture: String {
    case fullWeighing = "full-weighing-2026-10-04"
    case cutOffDuringBalance = "weighing-cut-off-during-balance-2026-10-04"

    private struct Line: Decodable {
        let hex: String
    }

    func decodedPackets() throws -> [ScalePacket] {
        guard let url = Bundle.module.url(forResource: rawValue, withExtension: "jsonl", subdirectory: "Fixtures") else {
            throw FixtureError.missing(rawValue)
        }
        let decoder = JSONDecoder()
        return try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n")
            .map { line in
                let hex = try decoder.decode(Line.self, from: Data(line.utf8)).hex
                guard let packet = ActiveEraProtocol.decode(try bytes(hex)) else { throw FixtureError.notAScalePacket(hex) }
                return packet
            }
    }
}

func bytes(_ hex: String) throws -> Data {
    let digits = Array(hex)
    guard digits.count.isMultiple(of: 2) else { throw FixtureError.invalidHex(hex) }
    return Data(try stride(from: 0, to: digits.count, by: 2).map { index in
        guard let byte = UInt8(String(digits[index...index + 1]), radix: 16) else { throw FixtureError.invalidHex(hex) }
        return byte
    })
}

func utc(_ iso8601: String) throws -> Date {
    try Date(iso8601, strategy: .iso8601)
}

extension ScalePacket {
    var isStableWeight: Bool {
        if case .liveWeight(_, true, _) = self { true } else { false }
    }

    var isHeartRate: Bool {
        if case .heartRate = self { true } else { false }
    }
}

extension MeasurementSession {
    @discardableResult
    mutating func consumeAll(_ packets: [ScalePacket]) -> [Duration?] {
        packets.map { consume($0) }
    }
}

extension Double {
    func rounded(places: Int) -> Double {
        let scale = pow(10, Double(places))
        return (self * scale).rounded() / scale
    }
}

extension BodyComposition {
    func rounded(places: Int) -> BodyComposition {
        var copy = self
        copy.bodyFatPercent = bodyFatPercent.rounded(places: places)
        copy.leanMassKg = leanMassKg.rounded(places: places)
        copy.musclePercent = musclePercent?.rounded(places: places)
        copy.skeletalMusclePercent = skeletalMusclePercent?.rounded(places: places)
        copy.waterPercent = waterPercent?.rounded(places: places)
        copy.proteinPercent = proteinPercent?.rounded(places: places)
        copy.boneMassKg = boneMassKg?.rounded(places: places)
        copy.visceralFat = visceralFat?.rounded(places: places)
        return copy
    }
}
