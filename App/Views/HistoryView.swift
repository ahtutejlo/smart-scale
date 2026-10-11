import Charts
import SwiftData
import SwiftUI

struct HistoryView: View {
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

    @Environment(SettingsStore.self) private var settings
    @Environment(WeighingRecorder.self) private var recorder
    @Query(sort: \Weighing.date) private var weighings: [Weighing]
    @Query(filter: #Predicate<Weighing> { $0.person == nil }, sort: \Weighing.date, order: .reverse) private var unassigned: [Weighing]
    @Query private var people: [Person]
    @State private var period = Period.month

    var body: some View {
        let calendar = Calendar.current
        let person = people.selected(settings.settings.selectedPersonID)
        let start = calendar.date(byAdding: .day, value: -period.rawValue, to: .now) ?? .distantPast
        let smoothingStart = calendar.date(byAdding: .day, value: -WeightAnalysis.trendWindowDays, to: start) ?? start
        let loaded = weighings.filter { $0.date >= smoothingStart && $0.person?.id == person?.id }
        let points = loaded.points
        let trend = WeightAnalysis.dailyTrend(points).filter { $0.day >= start }
        let comparison = WeightAnalysis.compositionComparison(points, overDays: period.rawValue, minimumDays: 1)
        let rows = zip(loaded, points)
            .filter { $0.0.date >= start }
            .reversed()
            .map { Row(weighing: $0.0, fatPercent: $0.1.fatPercent) }

        List {
            if !unassigned.isEmpty {
                Section {
                    ForEach(unassigned) { weighing in
                        Menu {
                            AssignActions(weighing: weighing, people: people)
                        } label: {
                            WeighingRow(weighing: weighing, fatPercent: nil)
                        }
                        .tint(.primary)
                    }
                } header: {
                    Text("Чиї це зважування?")
                } footer: {
                    Text("Торкнися зважування, щоб вибрати людину або видалити його.")
                }
            }
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
                    WeightChart(trend: trend, goalKg: person?.goalWeightKg)
                }
            }
            Section {
                if let comparison {
                    CompositionComparisonView(comparison: comparison)
                } else {
                    Text("Потрібні щонайменше два дні зважувань з % жиру.").foregroundStyle(.secondary)
                }
            } header: {
                Text("З чого складається вага")
            } footer: {
                Text("Маса без жиру — це м'язи, вода, кістки й органи. Кожне значення — середнє за \(WeightAnalysis.trendWindowDays.daysText), тому може трохи відрізнятися від окремого зважування.")
            }
            Section("Зважування") {
                ForEach(rows) { row in
                    NavigationLink {
                        WeighingDetailView(weighing: row.weighing)
                    } label: {
                        WeighingRow(weighing: row.weighing, fatPercent: row.fatPercent)
                    }
                }
                .onDelete { offsets in
                    offsets.forEach { recorder.discard(rows[$0].weighing) }
                }
            }
        }
        .navigationTitle("Історія")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                PersonPicker(people: people)
            }
        }
    }
}

private struct WeighingRow: View {
    let weighing: Weighing
    let fatPercent: Double?

    var body: some View {
        HStack {
            Image(systemName: weighing.sourceLabel.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .accessibilityLabel(weighing.sourceLabel.text)
            VStack(alignment: .leading) {
                Text(weighing.date.dayAndTime)
                if let fatPercent {
                    Text("жир \(fatPercent.percent)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(weighing.weightKg.kg).monospacedDigit().font(.body.weight(.semibold))
        }
    }
}

private struct WeightChart: View {
    let trend: [TrendPoint]
    let goalKg: Double?
    @State private var selectedDay: Date?

    private static let daily = "щоденна вага"
    private static let average = "середнє за \(WeightAnalysis.trendWindowDays.daysText)"

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

private struct CompositionComparisonView: View {
    let comparison: CompositionComparison

    var body: some View {
        let maxWeightKg = max(comparison.before.weightKg, comparison.after.weightKg)
        VStack(alignment: .leading, spacing: 14) {
            Text("За цей час: вага \(comparison.weightChangeKg.signedKg), жир \(comparison.fatChangeKg.signedKg), без жиру \(comparison.leanChangeKg.signedKg)")
                .font(.subheadline.weight(.semibold))
            SplitBar(title: comparison.before.day.shortDay, split: comparison.before, maxWeightKg: maxWeightKg)
            SplitBar(title: comparison.after.day.shortDay, split: comparison.after, maxWeightKg: maxWeightKg)
            HStack(spacing: 16) {
                legend("жир", color: ChartPalette.secondary)
                legend("без жиру", color: ChartPalette.primary)
            }
        }
        .padding(.vertical, 8)
    }

    private func legend(_ text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct SplitBar: View {
    let title: String
    let split: BodySplit
    let maxWeightKg: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(split.weightKg.kg).fontWeight(.semibold).monospacedDigit()
            }
            .font(.subheadline)
            GeometryReader { proxy in
                FatLeanBar(fatKg: split.fatKg, leanKg: split.leanKg)
                    .frame(width: proxy.size.width * split.weightKg / maxWeightKg)
            }
            .frame(height: 20)
            Text("жир \(split.fatKg.kg) · без жиру \(split.leanKg.kg)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
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
