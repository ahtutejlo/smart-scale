import Foundation
import Testing
@testable import ScaleKit

struct ConfigurationPacketTests {
    @Test func encodeMaleProfileWithGoalWeight() throws {
        let profile = UserProfile(heightCm: 180, age: 36, sex: .male, initialWeightKg: 88.0, goalWeightKg: 80.0)

        let packet = ActiveEraProtocol.configurationPacket(for: profile, at: try utc("2026-10-04T23:28:48Z"))

        #expect([UInt8](packet) == [
            0xAC, 0x27,
            0x6A, 0xC2, 0xE1, 0x30,
            0x04, 0x00, 0x01, 0xB4,
            0x22, 0x60,
            0x24, 0x01,
            0x1F, 0x40,
            0x03, 0x00, 0xD0,
            0xFF,
        ])
    }

    @Test func encodeFemaleProfileWithoutGoalWeightUsingInitialWeightAsGoal() throws {
        let profile = UserProfile(heightCm: 165, age: 29, sex: .female, initialWeightKg: 61.5)

        let packet = ActiveEraProtocol.configurationPacket(for: profile, at: try utc("2026-10-04T23:28:48Z"))

        #expect([UInt8](packet) == [
            0xAC, 0x27,
            0x6A, 0xC2, 0xE1, 0x30,
            0x04, 0x00, 0x01, 0xA5,
            0x18, 0x06,
            0x1D, 0x02,
            0x18, 0x06,
            0x03, 0x00, 0xD0,
            0x45,
        ])
    }

    @Test
    func encodeWeightAsNearestHundredthOfKilogram() throws {
        let profile = UserProfile(heightCm: 180, age: 36, sex: .male, initialWeightKg: 64.4)

        let packet = [UInt8](ActiveEraProtocol.configurationPacket(for: profile, at: try utc("2026-10-04T23:28:48Z")))

        #expect(packet[10...11] == [0x19, 0x28], "64.4 kg must be sent as 6440 hundredths")
    }
}
