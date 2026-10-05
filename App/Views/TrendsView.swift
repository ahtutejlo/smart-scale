import Charts
import SwiftData
import SwiftUI

struct TrendsView: View {
    enum Period: Int, CaseIterable {
        case week = 7
        case month = 30
        case quarter = 90
        case year = 365

        var title: String {
            switch self {
            case .week: "Тиждень"
            case .month: "Місяць"
            case .quarter: "3 місяці"
            case .year: "Рік"
            }
        }
    }

    private struct Row: Identifiable {
        let weighing: Weighing
        let fatPercent: Double?

        var id: PersistentIdentifier { weighing.persistentModelID }
    }

    @Environment(\.modelContext) private var context
    @Environment(ProfileStore.self) private var profile
    @Query(sort: \Weighing.date) private var weighings: [Weighing]
    @State private var period = Period.month

    var body: some View {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -period.rawValue, to: .now) ?? .distantPast
        let smoothingStart = calendar.date(byAdding: .day, value: -WeightAnalysis.trendWindowDays, to: start) ?? start
        let loaded = Array(weighings.drop { $0.date < smoothingStart })
        let points = loaded.points(for: profile.userProfile)
        let trend = WeightAnalysis.dailyTrend(points).filter { $0.day >= start }
        let composition = WeightAnalysis.compositionTrend(points, since: start)
        let rows = zip(loaded, points)
            .filter { $0.0.date >= start }
            .reversed()
            .map { Row(weighing: $0.0, fatPercent: $0.1.fatPercent) }

        List {
            Section {
                Picker("Період", selection: $period) {
                    ForEach(Period.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            Section("Вага") {
                if trend.isEmpty {
                    Text("За цей період зважувань немає.").foregroundStyle(.secondary)
                } else {
                    WeightChart(trend: trend, goalKg: profile.settings.goalWeightKg)
                }
            }
            Section {
                if composition.count < 2 {
                    Text("Потрібні щонайменше два дні зважувань з % жиру.").foregroundStyle(.secondary)
                } else {
                    CompositionChart(points: composition)
                }
            } header: {
                Text("Жир проти сухої маси")
            } footer: {
                Text("Зміна від першого дня періоду, згладжена за \(WeightAnalysis.trendWindowDays) днів. Суха маса — це все, крім жиру: м'язи, вода, кістки.")
            }
            Section("Зважування") {
                ForEach(rows) { WeighingRow(weighing: $0.weighing, fatPercent: $0.fatPercent) }
                    .onDelete { offsets in
                        offsets.forEach { context.delete(rows[$0].weighing) }
                    }
            }
        }
        .navigationTitle("Тренди")
    }
}

private struct WeighingRow: View {
    let weighing: Weighing
    let fatPercent: Double?

    var body: some View {
        HStack {
            Image(systemName: source.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .accessibilityLabel(source.label)
            VStack(alignment: .leading) {
                Text(weighing.date.formatted(date: .abbreviated, time: .shortened))
                if let fatPercent {
                    Text("жир \(fatPercent.percent)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(weighing.weightKg.kg).monospacedDigit().font(.body.weight(.semibold))
        }
    }

    private var source: (symbol: String, label: String) {
        switch weighing.source {
        case .scale: ("scalemass", "З ваг")
        case .scaleMemory: ("memorychip", "З пам'яті ваг")
        case .appleHealth: ("heart.text.square", "З Apple Health")
        }
    }
}

private struct WeightChart: View {
    let trend: [TrendPoint]
    let goalKg: Double?
    @State private var selectedDay: Date?

    private static let daily = "щоденна вага"
    private static let average = "середнє за \(WeightAnalysis.trendWindowDays) днів"

    var body: some View {
        Chart {
            ForEach(trend) { point in
                PointMark(x: .value("День", point.day, unit: .day), y: .value("Вага", point.weightKg))
                    .foregroundStyle(by: .value("Ряд", Self.daily))
                    .symbolSize(50)
            }
            ForEach(trend) { point in
                LineMark(x: .value("День", point.day, unit: .day), y: .value("Вага", point.trendKg))
                    .foregroundStyle(by: .value("Ряд", Self.average))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            if let goalKg, yDomain.contains(goalKg) {
                RuleMark(y: .value("Ціль", goalKg))
                    .foregroundStyle(Color(.secondaryLabel))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading) { ChartLabel(text: "Ціль \(goalKg.kg)") }
            }
            if let selected = trend.nearest(to: selectedDay) {
                SelectionRule(day: selected.day, lines: ["Вага \(selected.weightKg.kg)", "Тренд \(selected.trendKg.kg)"])
            }
        }
        .chartForegroundStyleScale([Self.daily: Color(.tertiaryLabel), Self.average: ChartPalette.primary])
        .chartLegend(position: .bottom, alignment: .leading)
        .chartYScale(domain: yDomain)
        .chartXSelection(value: $selectedDay)
        .frame(height: 260)
        .padding(.vertical, 8)
    }

    private var yDomain: ClosedRange<Double> {
        let values = trend.flatMap { [$0.weightKg, $0.trendKg] }
        var low = (values.min() ?? 0) - 0.5
        var high = (values.max() ?? 1) + 0.5
        if let goalKg, goalKg > low - 6, goalKg < high + 6 {
            low = min(low, goalKg - 0.5)
            high = max(high, goalKg + 0.5)
        }
        return low...high
    }
}

private struct CompositionChart: View {
    private struct Series: Identifiable {
        let name: String
        let value: KeyPath<CompositionPoint, Double>

        var id: String { name }
    }

    let points: [CompositionPoint]
    @State private var selectedDay: Date?

    private let series = [
        Series(name: "Жир", value: \.fatChangeKg),
        Series(name: "Суха маса", value: \.leanChangeKg),
    ]

    var body: some View {
        Chart {
            RuleMark(y: .value("Без змін", 0))
                .foregroundStyle(Color(.separator))
            ForEach(series) { series in
                ForEach(points) { point in
                    LineMark(x: .value("День", point.day, unit: .day), y: .value("Зміна, кг", point[keyPath: series.value]))
                        .foregroundStyle(by: .value("Показник", series.name))
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .interpolationMethod(.monotone)
                }
                if let last = points.last {
                    PointMark(x: .value("День", last.day, unit: .day), y: .value("Зміна, кг", last[keyPath: series.value]))
                        .foregroundStyle(by: .value("Показник", series.name))
                        .annotation(position: .trailing) { ChartLabel(text: series.name) }
                }
            }
            if let selected = points.nearest(to: selectedDay) {
                SelectionRule(
                    day: selected.day,
                    lines: ["Жир \(selected.fatChangeKg.signedKg)", "Суха маса \(selected.leanChangeKg.signedKg)"]
                )
            }
        }
        .chartForegroundStyleScale(["Жир": ChartPalette.secondary, "Суха маса": ChartPalette.primary])
        .chartLegend(position: .bottom, alignment: .leading)
        .chartXSelection(value: $selectedDay)
        .chartPlotStyle { $0.padding(.trailing, 72) }
        .frame(height: 220)
        .padding(.vertical, 8)
    }
}

private struct SelectionRule: ChartContent {
    let day: Date
    let lines: [String]

    var body: some ChartContent {
        RuleMark(x: .value("День", day, unit: .day))
            .foregroundStyle(Color(.separator))
            .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundStyle(.secondary)
                    ForEach(lines, id: \.self) { Text($0).font(.caption.weight(.semibold)).monospacedDigit() }
                }
                .padding(8)
                .background(.regularMaterial, in: .rect(cornerRadius: 8))
            }
    }
}

private struct ChartLabel: View {
    let text: String

    var body: some View {
        Text(text).font(.caption2).foregroundStyle(.secondary)
    }
}
