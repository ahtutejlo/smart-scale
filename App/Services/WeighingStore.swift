import Foundation
import SwiftData

@MainActor
struct WeighingStore {
    let context: ModelContext

    private static let duplicateWindow: TimeInterval = 180
    private static let duplicateWeightKg = 0.25

    @discardableResult
    func insert(_ candidates: [Weighing]) -> [Weighing] {
        let dates = candidates.map(\.date)
        guard let earliest = dates.min(), let latest = dates.max() else { return [] }
        let from = earliest.addingTimeInterval(-Self.duplicateWindow)
        let to = latest.addingTimeInterval(Self.duplicateWindow)
        let existing = (try? context.fetch(FetchDescriptor<Weighing>(predicate: #Predicate { $0.date >= from && $0.date <= to }))) ?? []
        var byMinute = Dictionary(grouping: existing) { Self.minute($0.date) }
        var inserted: [Weighing] = []
        for candidate in candidates {
            let minute = Self.minute(candidate.date)
            let twin = (minute - 3...minute + 3).lazy
                .flatMap { byMinute[$0] ?? [] }
                .first { Self.isDuplicate($0, candidate) }
            let twinOwner = twin?.person
            if let twin {
                guard twin.source == .appleHealth, candidate.source != .appleHealth else { continue }
                context.delete(twin)
                byMinute[Self.minute(twin.date)]?.removeAll { $0 === twin }
            }
            context.insert(candidate)
            candidate.person = twinOwner
            byMinute[minute, default: []].append(candidate)
            inserted.append(candidate)
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
