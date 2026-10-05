import Foundation

struct WeighingPoint: Sendable {
    let date: Date
    let weightKg: Double
    let fatPercent: Double?
}

protocol DayPoint: Identifiable, Sendable where ID == Date {
    var day: Date { get }
}

extension DayPoint {
    var id: Date { day }
}

struct TrendPoint: DayPoint {
    let day: Date
    let weightKg: Double
    let trendKg: Double
}

struct CompositionPoint: DayPoint {
    let day: Date
    let fatChangeKg: Double
    let leanChangeKg: Double
}

struct CompositionChange: Sendable {
    let fatKg: Double
    let leanKg: Double
    let days: Int
}

enum CompositionVerdict: Sendable {
    case losingFat
    case losingLean
    case gainingBoth
    case gainingFat
    case gainingLean
    case stable
}

enum GoalForecast: Equatable, Sendable {
    case noGoal
    case reached
    case notEnoughData
    case movingAway
    case tooSlow
    case eta(date: Date, goalKg: Double)
}

extension Collection where Element: DayPoint {
    func nearest(to day: Date?) -> Element? {
        guard let day else { return nil }
        return self.min { abs($0.day.timeIntervalSince(day)) < abs($1.day.timeIntervalSince(day)) }
    }
}

extension Collection where Element == Double {
    var mean: Double {
        isEmpty ? 0 : reduce(0, +) / Double(count)
    }
}

enum WeightAnalysis {
    static let trendWindowDays = 7
    static let rateWindowDays = 28
    static let minimumRateDays = 4
    static let minimumRateSpanDays = 7
    static let compositionWindowDays = 30
    static let analysisHistoryDays = 60

    static func dailyTrend(_ points: [WeighingPoint], calendar: Calendar = .current) -> [TrendPoint] {
        let daily = groupedByDay(points, calendar: calendar)
        let weights = daily.map { $0.points.map(\.weightKg).mean }
        let smoothed = trailingMeans(daily.map(\.day), weights, calendar: calendar)
        return zip(daily, zip(weights, smoothed)).map { TrendPoint(day: $0.day, weightKg: $1.0, trendKg: $1.1) }
    }

    static func change(_ trend: [TrendPoint], overDays days: Int, calendar: Calendar = .current) -> Double? {
        guard let last = trend.last,
              let target = calendar.date(byAdding: .day, value: -days, to: last.day),
              let earlier = trend.last(where: { $0.day <= target }) else { return nil }
        return last.trendKg - earlier.trendKg
    }

    static func weeklyRateKg(_ trend: [TrendPoint], calendar: Calendar = .current) -> Double? {
        guard let last = trend.last,
              let earliest = calendar.date(byAdding: .day, value: -rateWindowDays, to: last.day) else { return nil }
        let window = trend.filter { $0.day >= earliest }
        guard window.count >= minimumRateDays, let first = window.first,
              days(from: first.day, to: last.day, calendar: calendar) >= minimumRateSpanDays else { return nil }
        let xs = window.map { Double(days(from: first.day, to: $0.day, calendar: calendar)) }
        let ys = window.map(\.weightKg)
        let meanX = xs.mean
        let meanY = ys.mean
        let covariance = zip(xs, ys).reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) }
        let variance = xs.reduce(0) { $0 + ($1 - meanX) * ($1 - meanX) }
        guard variance > 0 else { return nil }
        return covariance / variance * 7
    }

    static func forecast(
        currentKg: Double?,
        weeklyRateKg: Double?,
        goalKg: Double?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> GoalForecast {
        guard let goalKg else { return .noGoal }
        guard let currentKg else { return .notEnoughData }
        let remaining = goalKg - currentKg
        if abs(remaining) < 0.3 { return .reached }
        guard let weeklyRateKg else { return .notEnoughData }
        if abs(weeklyRateKg) < 0.05 { return .tooSlow }
        if remaining.sign != weeklyRateKg.sign { return .movingAway }
        let weeks = remaining / weeklyRateKg
        guard weeks <= 156, let date = calendar.date(byAdding: .day, value: Int((weeks * 7).rounded()), to: now) else {
            return .tooSlow
        }
        return .eta(date: date, goalKg: goalKg)
    }

    static func compositionTrend(_ points: [WeighingPoint], since start: Date, calendar: Calendar = .current) -> [CompositionPoint] {
        let daily = groupedByDay(points.filter { $0.fatPercent != nil }, calendar: calendar)
        let days = daily.map(\.day)
        let fat = trailingMeans(days, daily.map { $0.points.map { masses($0).fat }.mean }, calendar: calendar)
        let lean = trailingMeans(days, daily.map { $0.points.map { masses($0).lean }.mean }, calendar: calendar)
        guard let base = days.firstIndex(where: { $0 >= start }) else { return [] }
        return (base..<days.count).map {
            CompositionPoint(day: days[$0], fatChangeKg: fat[$0] - fat[base], leanChangeKg: lean[$0] - lean[base])
        }
    }

    static func compositionChange(_ points: [WeighingPoint], now: Date = .now, calendar: Calendar = .current) -> CompositionChange? {
        guard let start = calendar.date(byAdding: .day, value: -compositionWindowDays, to: now) else { return nil }
        let window = points.filter { $0.date >= start && $0.fatPercent != nil }.sorted { $0.date < $1.date }
        guard window.count >= 2, let first = window.first, let last = window.last else { return nil }
        let span = days(from: first.date, to: last.date, calendar: calendar)
        guard span >= minimumRateSpanDays else { return nil }
        let sampleSize = min(3, window.count / 2)
        let before = window.prefix(sampleSize).map(masses)
        let after = window.suffix(sampleSize).map(masses)
        return CompositionChange(
            fatKg: after.map { $0.fat }.mean - before.map { $0.fat }.mean,
            leanKg: after.map { $0.lean }.mean - before.map { $0.lean }.mean,
            days: span
        )
    }

    static func verdict(_ change: CompositionChange) -> CompositionVerdict {
        let threshold = 0.3
        return switch (change.fatKg, change.leanKg) {
        case let (fat, lean) where fat < -threshold && lean >= -threshold: .losingFat
        case let (fat, lean) where fat < -threshold && lean < -threshold: .losingLean
        case let (fat, lean) where fat > threshold && lean > threshold: .gainingBoth
        case let (fat, _) where fat > threshold: .gainingFat
        case let (_, lean) where lean > threshold: .gainingLean
        default: .stable
        }
    }

    private static func groupedByDay(_ points: [WeighingPoint], calendar: Calendar) -> [(day: Date, points: [WeighingPoint])] {
        Dictionary(grouping: points) { calendar.startOfDay(for: $0.date) }
            .map { (day: $0.key, points: $0.value) }
            .sorted { $0.day < $1.day }
    }

    private static func trailingMeans(_ days: [Date], _ values: [Double], calendar: Calendar) -> [Double] {
        var means: [Double] = []
        var windowStart = 0
        var windowSum = 0.0
        for index in days.indices {
            windowSum += values[index]
            let earliest = calendar.date(byAdding: .day, value: -(trendWindowDays - 1), to: days[index]) ?? days[index]
            while days[windowStart] < earliest {
                windowSum -= values[windowStart]
                windowStart += 1
            }
            means.append(windowSum / Double(index - windowStart + 1))
        }
        return means
    }

    private static func days(from start: Date, to end: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    private static func masses(_ point: WeighingPoint) -> (fat: Double, lean: Double) {
        let fat = point.weightKg * (point.fatPercent ?? 0) / 100
        return (fat, point.weightKg - fat)
    }
}
