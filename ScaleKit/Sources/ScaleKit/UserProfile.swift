import Foundation

public struct UserProfile: Codable, Equatable, Sendable {
    public enum Sex: String, Codable, Sendable {
        case male
        case female
    }

    public var heightCm: Int
    public var age: Int
    public var sex: Sex
    public var initialWeightKg: Double
    public var goalWeightKg: Double?

    public init(heightCm: Int, age: Int, sex: Sex, initialWeightKg: Double, goalWeightKg: Double? = nil) {
        self.heightCm = heightCm
        self.age = age
        self.sex = sex
        self.initialWeightKg = initialWeightKg
        self.goalWeightKg = goalWeightKg
    }
}
