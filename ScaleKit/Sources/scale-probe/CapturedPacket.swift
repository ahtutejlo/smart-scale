import Foundation

public struct CapturedPacket: Codable, Equatable, Sendable {
    public var ms: Int
    public var hex: String

    public init(ms: Int, data: Data) {
        self.ms = ms
        hex = data.map { String(format: "%02x", $0) }.joined()
    }

    public var data: Data? {
        guard hex.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return Data(bytes)
    }
}
