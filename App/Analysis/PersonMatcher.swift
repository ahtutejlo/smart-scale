import Foundation

enum PersonMatcher {
    static let toleranceKg = 3.5

    static func match<ID: Hashable>(weightKg: Double, latestWeights: [ID: Double]) -> ID? {
        let candidates = latestWeights.filter { fits(weightKg: weightKg, usualKg: $0.value) }
        return candidates.count == 1 ? candidates.first?.key : nil
    }

    static func fits(weightKg: Double, usualKg: Double) -> Bool {
        abs(usualKg - weightKg) <= toleranceKg
    }
}
