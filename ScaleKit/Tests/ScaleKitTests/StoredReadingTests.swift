import Foundation
import Testing
@testable import ScaleKit

struct StoredRecordCase: Sendable, CustomTestStringConvertible {
    let recordedAt: String
    let leftLegKg: Double
    let heartRate: Int
    let rawImpedance: Int
    let expectedLeftLegPercent: Double
    let expectedImpedanceOhm: Double

    var testDescription: String { "stored record \(recordedAt)" }
}

struct StoredReadingTests {
    @Test(arguments: [
        StoredRecordCase(recordedAt: "2026-10-04T23:28:48Z", leftLegKg: 43.3, heartRate: 100, rawImpedance: 4934,
                         expectedLeftLegPercent: 49.19, expectedImpedanceOhm: 596.99),
        StoredRecordCase(recordedAt: "2026-10-04T23:31:09Z", leftLegKg: 41.8, heartRate: 83, rawImpedance: 4172,
                         expectedLeftLegPercent: 47.49, expectedImpedanceOhm: 469.99),
    ])
    func convertStoredRecordToReading(_ record: StoredRecordCase) throws {
        let recordedAt = try utc(record.recordedAt)

        let reading = ScaleReading(StoredMeasurement(
            date: recordedAt, weightKg: 88.02, leftLegKg: record.leftLegKg,
            heartRate: record.heartRate, rawImpedance: record.rawImpedance, algorithm: 0x07
        ))

        #expect(reading.date == recordedAt)
        #expect(reading.weightKg == 88.02)
        #expect(reading.leftLegPercent?.rounded(places: 2) == record.expectedLeftLegPercent, "left leg share of body weight, in %")
        #expect(reading.impedanceOhm?.rounded(places: 2) == record.expectedImpedanceOhm, "raw impedance corrected for body weight")
        #expect(reading.heartRate == record.heartRate)
        #expect(reading.algorithm == 0x07)
    }

    @Test func convertZeroWeightRecordWithoutBalance() {
        let reading = ScaleReading(StoredMeasurement(
            date: .now, weightKg: 0, leftLegKg: 0, heartRate: nil, rawImpedance: 0, algorithm: 0x07
        ))

        #expect(reading.leftLegPercent == nil, "no balance share can be computed from a zero weight")
    }
}
