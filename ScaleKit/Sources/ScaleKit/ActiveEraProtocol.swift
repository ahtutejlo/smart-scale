import Foundation

public enum ScalePacket: Equatable, Sendable {
    case liveWeight(kg: Double, isStable: Bool, reportsHeartRate: Bool)
    case balance(leftPercent: Double, leftKg: Double, isFinal: Bool)
    case impedance(raw: Int, algorithm: UInt8)
    case heartRate(bpm: Int)
    case stored(StoredMeasurement)
    case unknown(type: UInt8)
}

public struct StoredMeasurement: Equatable, Sendable {
    public var date: Date
    public var weightKg: Double
    public var leftLegKg: Double
    public var heartRate: Int?
    public var rawImpedance: Int
    public var algorithm: UInt8
}

public enum ActiveEraProtocol {
    static let serviceUUID = "FFB0"
    static let writeCharacteristicUUID = "FFB1"
    static let notifyCharacteristicUUID = "FFB2"

    static let magic: UInt8 = 0xAC
    static let deviceType: UInt8 = 0x27
    static let packetLength = 20

    public static func decode(_ data: Data) -> ScalePacket? {
        let bytes = [UInt8](data)
        guard bytes.count == packetLength, bytes[0] == magic else { return nil }
        let type = bytes[0x12]
        switch type {
        case 0xD5:
            return .liveWeight(
                kg: Double(uint(bytes, at: 3, width: 3) & 0x3FFFF) / 1000,
                isStable: bytes[2] & 0x80 != 0,
                reportsHeartRate: bytes[2] & 0x02 != 0
            )
        case 0xD0:
            return .balance(
                leftPercent: Double(uint(bytes, at: 5, width: 2)) / 10,
                leftKg: Double(uint(bytes, at: 3, width: 2)) / 100,
                isFinal: bytes[2] == 0x01
            )
        case 0xD6 where bytes[2] == 1:
            return .impedance(raw: uint(bytes, at: 4, width: 2), algorithm: bytes[0x11])
        case 0xD7:
            return .heartRate(bpm: Int(bytes[3]))
        case 0xD8:
            return .stored(StoredMeasurement(
                date: Date(timeIntervalSince1970: TimeInterval(uint(bytes, at: 3, width: 4))),
                weightKg: Double(uint(bytes, at: 8, width: 3) & 0x3FFFF) / 1000,
                leftLegKg: Double(uint(bytes, at: 11, width: 2)) / 100,
                heartRate: bytes[13] == 0 ? nil : Int(bytes[13]),
                rawImpedance: uint(bytes, at: 15, width: 2),
                algorithm: bytes[17]
            ))
        default:
            return .unknown(type: type)
        }
    }

    public static func impedanceOhm(raw: Int, weightKg: Double) -> Double {
        let value = Double(raw)
        guard value >= 1500 else { return value }
        return ((value - 1000) + weightKg * 10 * -0.4) / 0.6 / 10
    }

    public static func configurationPacket(for profile: UserProfile, at date: Date) -> Data {
        let seconds = UInt32(clamping: Int(date.timeIntervalSince1970))
        let initialWeight = hundredths(profile.initialWeightKg)
        let goalWeight = profile.goalWeightKg.map(hundredths) ?? initialWeight

        var packet: [UInt8] = [magic, deviceType]
        packet += bigEndian(seconds)
        packet += [0x04, 0x00, 0x01, UInt8(clamping: profile.heightCm)]
        packet += bigEndian(initialWeight)
        packet += [UInt8(clamping: profile.age), profile.sex == .male ? 0x01 : 0x02]
        packet += bigEndian(goalWeight)
        packet += [0x03, 0x00, 0xD0]
        packet.append(packet[2..<17].reduce(0, &+))
        return Data(packet)
    }

    private static func uint(_ bytes: [UInt8], at offset: Int, width: Int) -> Int {
        bytes[offset..<offset + width].reduce(0) { $0 << 8 | Int($1) }
    }

    private static func hundredths(_ kg: Double) -> UInt16 {
        UInt16(clamping: Int((kg * 100).rounded()))
    }

    private static func bigEndian<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
        withUnsafeBytes(of: value.bigEndian, Array.init)
    }
}
