import Foundation
import Testing
@testable import ScaleKit

struct PacketCase: Sendable, CustomTestStringConvertible {
    let name: String
    let hex: String
    var expected: ScalePacket? = nil

    var testDescription: String { name }
}

struct PacketDecodingTests {
    @Test(arguments: [
        PacketCase(name: "D5 weight still settling", hex: "ac27068d5914000000000000000000000007d51c",
                   expected: .liveWeight(kg: 88.34, isStable: false, reportsHeartRate: true)),
        PacketCase(name: "D5 stable weight", hex: "ac27868d57c0000000000000000000000007d506",
                   expected: .liveWeight(kg: 88.0, isStable: true, reportsHeartRate: true)),
        PacketCase(name: "D5 stable weight, heart-rate flag off", hex: "ac27848d57c0000000000000000000000007d506",
                   expected: .liveWeight(kg: 88.0, isStable: true, reportsHeartRate: false)),
        PacketCase(name: "D0 balance in progress", hex: "ac2700111201f10000000000000000000000d005",
                   expected: .balance(leftPercent: 49.7, leftKg: 43.7, isFinal: false)),
        PacketCase(name: "D0 final balance", hex: "ac2701125c02160000000000000000000000d017",
                   expected: .balance(leftPercent: 53.4, leftKg: 47.0, isFinal: true)),
        PacketCase(name: "D6 impedance", hex: "ac270100101c000000000000000000000007d60a",
                   expected: .impedance(raw: 4124, algorithm: 0x07)),
        PacketCase(name: "D7 heart rate", hex: "ac2700540000000000000000000000000000d70b",
                   expected: .heartRate(bpm: 84)),
        PacketCase(name: "D8 stored record, 4-byte big-endian timestamp", hex: "ac27006ac2e130868d57d410ea6401134607d812",
                   expected: .stored(StoredMeasurement(date: try utc("2026-10-04T23:28:48Z"), weightKg: 88.02, leftLegKg: 43.3,
                                                       heartRate: 100, rawImpedance: 4934, algorithm: 0x07))),
        PacketCase(name: "D8 second stored record, 4-byte big-endian timestamp", hex: "ac27006ac2e1bd868d57d410545301104c07d81b",
                   expected: .stored(StoredMeasurement(date: try utc("2026-10-04T23:31:09Z"), weightKg: 88.02, leftLegKg: 41.8,
                                                       heartRate: 83, rawImpedance: 4172, algorithm: 0x07))),
        PacketCase(name: "D8 stored record, heart-rate byte 0", hex: "ac27006ac2e130868d57d410ea0001134607d812",
                   expected: .stored(StoredMeasurement(date: try utc("2026-10-04T23:28:48Z"), weightKg: 88.02, leftLegKg: 43.3,
                                                       heartRate: nil, rawImpedance: 4934, algorithm: 0x07))),
    ])
    func decodeKnownPacketToExactValues(_ packet: PacketCase) throws {
        #expect(ActiveEraProtocol.decode(try bytes(packet.hex)) == packet.expected)
    }

    @Test(arguments: [
        PacketCase(name: "D6 with count byte 2", hex: "ac270200101c000000000000000000000007d60a", expected: .unknown(type: 0xD6)),
        PacketCase(name: "D6 with count byte 0", hex: "ac270000101c000000000000000000000007d60a", expected: .unknown(type: 0xD6)),
        PacketCase(name: "type 0xD9", hex: "ac27868d57c0000000000000000000000007d906", expected: .unknown(type: 0xD9)),
    ])
    func decodeUnsupportedPacketAsUnknown(_ packet: PacketCase) throws {
        #expect(ActiveEraProtocol.decode(try bytes(packet.hex)) == packet.expected)
    }

    @Test(arguments: [
        PacketCase(name: "empty", hex: ""),
        PacketCase(name: "19 bytes", hex: "ac27868d57c0000000000000000000000007d5"),
        PacketCase(name: "21 bytes", hex: "ac27868d57c0000000000000000000000007d50600"),
        PacketCase(name: "magic byte 0xAB", hex: "ab27868d57c0000000000000000000000007d506"),
    ])
    func rejectPacketWithWrongLengthOrMagic(_ packet: PacketCase) throws {
        #expect(ActiveEraProtocol.decode(try bytes(packet.hex)) == nil)
    }
}
