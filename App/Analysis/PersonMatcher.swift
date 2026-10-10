import Foundation

enum PersonMatcher {
    static let toleranceKg = 3.5

    static func match<ID: Hashable>(weightKg: Double, latestWeights: [ID: Double]) -> ID? {
        let candidates = latestWeights.filter { abs($0.value - weightKg) <= toleranceKg }
        return candidates.count == 1 ? candidates.first?.key : nil
    }
}
