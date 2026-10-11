import Foundation
import ScaleKit
import SwiftData

@Model
final class Person {
    var id: UUID
    var name: String
    var sex: UserProfile.Sex
    var age: Int?
    var heightCm: Int?
    var goalWeightKg: Double?
    var goalStartWeightKg: Double?
    var isOwner: Bool
    @Relationship(deleteRule: .nullify, inverse: \Weighing.person) var weighings: [Weighing] = []

    init(
        name: String,
        sex: UserProfile.Sex = .male,
        age: Int? = nil,
        heightCm: Int? = nil,
        goalWeightKg: Double? = nil,
        isOwner: Bool = false
    ) {
        id = UUID()
        self.name = name
        self.sex = sex
        self.age = age
        self.heightCm = heightCm
        self.goalWeightKg = goalWeightKg
        self.isOwner = isOwner
    }

    var displayName: String {
        name.isEmpty ? "Без імені" : name
    }

    var userProfile: UserProfile? {
        guard let age = age.positive, let heightCm = heightCm.positive else { return nil }
        return UserProfile(heightCm: heightCm, age: age, sex: sex, initialWeightKg: goalWeightKg ?? 75, goalWeightKg: goalWeightKg)
    }

    var latestWeightKg: Double? {
        weighings.max { $0.date < $1.date }?.weightKg
    }

    func usualWeightKg(near date: Date, excluding weighing: Weighing) -> Double? {
        weighings
            .filter { $0 !== weighing }
            .min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }?
            .weightKg
    }

    func syncGoalStart() {
        if goalWeightKg == nil {
            goalStartWeightKg = nil
        } else if goalStartWeightKg == nil {
            goalStartWeightKg = latestWeightKg
        }
    }
}

extension Sequence where Element == Person {
    func ownerFirst() -> [Person] {
        sorted { ($0.isOwner ? 0 : 1, $0.name) < ($1.isOwner ? 0 : 1, $1.name) }
    }

    var owner: Person? {
        first { $0.isOwner }
    }

    func selected(_ id: UUID?) -> Person? {
        first { $0.id == id } ?? owner
    }

    func matching(weightKg: Double) -> Person? {
        let latestWeights = Dictionary(uniqueKeysWithValues: compactMap { person in
            person.latestWeightKg.map { (person.id, $0) }
        })
        let matchedID = PersonMatcher.match(weightKg: weightKg, latestWeights: latestWeights)
        return first { $0.id == matchedID }
    }
}

extension Optional where Wrapped == Int {
    var positive: Int? {
        flatMap { $0 > 0 ? $0 : nil }
    }
}
