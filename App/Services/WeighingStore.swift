import Foundation
import SwiftData

@MainActor
struct WeighingStore {
    let context: ModelContext

    private static let duplicateWindow: TimeInterval = 180
    private static let duplicateWeightKg = 0.25

    func latest() -> Weighing? {
        (try? context.fetch(.newest(limit: 1)))?.first
    }

    @discardableResult
    func insert(_ candidates: [Weighing]) -> Int {
        let dates = candidates.map(\.date)
        guard let earliest = dates.min(), let latest = dates.max() else { return 0 }
        let from = earliest.addingTimeInterval(-Self.duplicateWindow)
        let to = latest.addingTimeInterval(Self.duplicateWindow)
        let existing = (try? context.fetch(FetchDescriptor<Weighing>(predicate: #Predicate { $0.date >= from && $0.date <= to }))) ?? []
        var byMinute = Dictionary(grouping: existing) { Self.minute($0.date) }
        var inserted = 0
        for candidate in candidates {
            let minute = Self.minute(candidate.date)
            let twin = (minute - 3...minute + 3).lazy
                .flatMap { byMinute[$0] ?? [] }
                .first { Self.isDuplicate($0, candidate) }
            if let twin {
                guard twin.source == .appleHealth, candidate.source != .appleHealth else { continue }
                context.delete(twin)
                byMinute[Self.minute(twin.date)]?.removeAll { $0 === twin }
            }
            context.insert(candidate)
            byMinute[minute, default: []].append(candidate)
            inserted += 1
        }
        return inserted
    }

    private static func minute(_ date: Date) -> Int {
        Int(date.timeIntervalSince1970 / 60)
    }

    private static func isDuplicate(_ existing: Weighing, _ candidate: Weighing) -> Bool {
        abs(existing.date.timeIntervalSince(candidate.date)) <= duplicateWindow
            && abs(existing.weightKg - candidate.weightKg) < duplicateWeightKg
    }
}
