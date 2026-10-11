import Foundation

struct WeighingPoint: Sendable {
    let date: Date
    let weightKg: Double
    let fatPercent: Double?
}

struct TrendPoint: Identifiable, Sendable {
    let day: Date
    let weightKg: Double
    let trendKg: Double

    var id: Date { day }
}

struct BodySplit: Sendable {
    let day: Date
    let fatKg: Double
    let leanKg: Double

    var weightKg: Double { fatKg + leanKg }
}

struct CompositionComparison: Sendable {
    let before: BodySplit
    let after: BodySplit
    let days: Int

    var weightChangeKg: Double { after.weightKg - before.weightKg }
    var fatChangeKg: Double { after.fatKg - before.fatKg }
    var leanChangeKg: Double { after.leanKg - before.leanKg }
}

enum CompositionVerdict: Sendable {
    case losingMostlyFat(fatShare: Double)
    case losingMuchLean(fatShare: Double)
    case losingNoFat
    case gainingMostlyFat(fatShare: Double)
    case gainingMostlyLean
    case lessFatSameWeight
    case moreFatSameWeight
    case stable
}

enum TrendDeviation: Sendable {
    case matches
    case water(Double)
    case food(Double)
    case large(Double)
}

struct GoalProgress: Sendable {
    let startKg: Double
    let goalKg: Double
    let currentKg: Double

    init?(startKg: Double?, goalKg: Double?, currentKg: Double?) {
        guard let startKg, let goalKg, let currentKg, abs(goalKg - startKg) >= 0.1 else { return nil }
        self.startKg = startKg
        self.goalKg = goalKg
        self.currentKg = currentKg
    }

    var doneKg: Double { goalKg < startKg ? startKg - currentKg : currentKg - startKg }
    var remainingKg: Double { abs(goalKg - currentKg) }
    var fraction: Double { min(max(doneKg / abs(goalKg - startKg), 0), 1) }
}

enum GoalForecast: Equatable, Sendable {
    case noGoal
    case reached
    case notEnoughData
    case movingAway
    case tooSlow
    case eta(earliest: Date, latest: Date)
}

extension Collection where Element == TrendPoint {
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
    static let compositionWindowDays = 28
    static let compositionMinimumDays = 21
    static let analysisHistoryDays = 60
    static let forecastSpread = 0.8...1.25
    static let mostlyFatShare = 0.6

    static func dailyTrend(_ points: [WeighingPoint], calendar: Calendar = .current) -> [TrendPoint] {
        let daily = groupedByDay(points, calendar: calendar)
        let weights = daily.map { $0.points.map(\.weightKg).mean }
        let smoothed = trailingMeans(daily.map(\.day), weights, calendar: calendar)
        return zip(daily, zip(weights, smoothed)).map { TrendPoint(day: $0.day, weightKg: $1.0, trendKg: $1.1) }
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
        let days = remaining / weeklyRateKg * 7
        guard days <= 156 * 7,
              let earliest = calendar.date(byAdding: .day, value: Int((days * forecastSpread.lowerBound).rounded()), to: now),
              let latest = calendar.date(byAdding: .day, value: Int((days * forecastSpread.upperBound).rounded()), to: now) else {
            return .tooSlow
        }
        return .eta(earliest: earliest, latest: latest)
    }

    static func compositionComparison(
        _ points: [WeighingPoint],
        overDays windowDays: Int,
        minimumDays: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> CompositionComparison? {
        guard let start = calendar.date(byAdding: .day, value: -windowDays, to: now) else { return nil }
        let daily = groupedByDay(points.filter { $0.fatPercent != nil }, calendar: calendar)
        let dates = daily.map(\.day)
        let fat = trailingMeans(dates, daily.map { $0.points.map { masses($0).fat }.mean }, calendar: calendar)
        let lean = trailingMeans(dates, daily.map { $0.points.map { masses($0).lean }.mean }, calendar: calendar)
        guard let first = dates.firstIndex(where: { $0 >= start }), let last = dates.indices.last else { return nil }
        let span = days(from: dates[first], to: dates[last], calendar: calendar)
        guard span >= minimumDays else { return nil }
        return CompositionComparison(
            before: BodySplit(day: dates[first], fatKg: fat[first], leanKg: lean[first]),
            after: BodySplit(day: dates[last], fatKg: fat[last], leanKg: lean[last]),
            days: span
        )
    }

    static func verdict(_ comparison: CompositionComparison) -> CompositionVerdict {
        let threshold = 0.5
        let weight = comparison.weightChangeKg
        let fat = comparison.fatChangeKg
        if weight <= -threshold {
            let share = fat / weight
            if share >= mostlyFatShare { return .losingMostlyFat(fatShare: share) }
            return share > 0 ? .losingMuchLean(fatShare: share) : .losingNoFat
        }
        if weight >= threshold {
            let share = fat / weight
            return share >= mostlyFatShare ? .gainingMostlyFat(fatShare: share) : .gainingMostlyLean
        }
        if fat <= -threshold { return .lessFatSameWeight }
        if fat >= threshold { return .moreFatSameWeight }
        return .stable
    }

    static func trendDeviation(of point: WeighingPoint, history: [WeighingPoint], calendar: Calendar = .current) -> TrendDeviation? {
        guard let start = calendar.date(byAdding: .day, value: -trendWindowDays, to: point.date) else { return nil }
        let earlier = history.filter { $0.date >= start && $0.date < point.date }
        guard let trendKg = dailyTrend(earlier, calendar: calendar).last?.trendKg else { return nil }
        let difference = point.weightKg - trendKg
        return switch abs(difference) {
        case ..<0.1: .matches
        case ..<1: .water(difference)
        case ..<3: .food(difference)
        default: .large(difference)
        }
    }

    static func streakDays(_ dates: [Date], today: Date = .now, calendar: Calendar = .current) -> Int {
        let weighedDays = Set(dates.map { calendar.startOfDay(for: $0) })
        var day = calendar.startOfDay(for: today)
        if !weighedDays.contains(day), let yesterday = calendar.date(byAdding: .day, value: -1, to: day) {
            day = yesterday
        }
        var count = 0
        while weighedDays.contains(day), let previous = calendar.date(byAdding: .day, value: -1, to: day) {
            count += 1
            day = previous
        }
        return count
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
