import Charts
import ScaleKit
import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(SettingsStore.self) private var settings
    @Query private var recent: [Weighing]
    @Query private var people: [Person]

    init() {
        let start = Calendar.current.date(byAdding: .day, value: -WeightAnalysis.analysisHistoryDays, to: .now) ?? .distantPast
        _recent = Query(filter: #Predicate<Weighing> { $0.date >= start }, sort: \.date)
    }

    var body: some View {
        let person = people.selected(settings.settings.selectedPersonID)
        let weighings = recent.belonging(to: person)
        let points = weighings.points
        let trend = WeightAnalysis.dailyTrend(points)
        let rate = WeightAnalysis.weeklyRateKg(trend)
        let currentKg = trend.last?.trendKg
        let goalKg = person?.goalWeightKg
        let forecast = WeightAnalysis.forecast(currentKg: currentKg, weeklyRateKg: rate, goalKg: goalKg)

        ScrollView {
            VStack(spacing: 16) {
                LiveSection(people: people, recent: recent)
                if person?.userProfile == nil {
                    Card(title: "Спершу профіль") {
                        Text("Вкажи вік і зріст у вкладці «Люди». Без них не порахувати склад тіла.")
                    }
                }
                TrendCard(trend: trend, rate: rate, forecast: forecast)
                GoalCard(
                    goalKg: goalKg,
                    progress: GoalProgress(startKg: person?.goalStartWeightKg, goalKg: goalKg, currentKg: currentKg),
                    forecast: forecast
                )
                CompositionCard(comparison: WeightAnalysis.compositionComparison(
                    points,
                    overDays: WeightAnalysis.compositionWindowDays,
                    minimumDays: WeightAnalysis.compositionMinimumDays
                ))
                if let last = weighings.last {
                    LastWeighingRow(weighing: last)
                }
                if let person {
                    StreakLine(days: WeightAnalysis.streakDays(person.weighings.map(\.date)))
                }
            }
            .padding()
        }
        .navigationTitle("Сьогодні")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                PersonPicker(people: people)
            }
        }
    }
}

private struct LiveSection: View {
    let people: [Person]
    let recent: [Weighing]
    @Environment(SettingsStore.self) private var settings
    @Environment(WeighingRecorder.self) private var recorder
    @Query(.newest(limit: 1)) private var latest: [Weighing]

    var body: some View {
        let justWeighed = latest.first.flatMap { recorder.isJustFinished($0) ? $0 : nil }
        VStack(spacing: 16) {
            status
            if let weighing = latest.first, weighing.person == nil {
                UnassignedCard(weighing: weighing, people: people)
            } else if let justWeighed {
                JustWeighedCard(weighing: justWeighed, people: people, history: recent.belonging(to: justWeighed.person).points)
            }
        }
        .onChange(of: justWeighed?.person?.id, initial: true) { _, id in
            if let id {
                settings.settings.selectedPersonID = id
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        switch recorder.connection.state {
        case .idle, .searching:
            StatusLine(symbol: "scalemass", text: "Ваги чекають. Стань босоніж.", isWorking: true)
        case .connecting:
            StatusLine(symbol: "antenna.radiowaves.left.and.right", text: "Підключаюся до ваг…", isWorking: true)
        case let .measuring(liveKg):
            MeasuringCard(liveKg: liveKg)
        case .finished:
            StatusLine(symbol: "checkmark.circle.fill", text: "Готово. Можна зійти з ваг.")
        case let .bluetoothUnavailable(problem):
            StatusLine(symbol: "exclamationmark.triangle", text: "Bluetooth недоступний. \(problem.explanation)", isProblem: true)
        }
    }
}

private extension ScaleConnection.BluetoothProblem {
    var explanation: String {
        switch self {
        case .poweredOff: "Увімкни Bluetooth у Пункті керування."
        case .unauthorized: "Дозволь апці доступ до Bluetooth у Параметрах → Ваги."
        case .unsupported: "Цей пристрій не підтримує Bluetooth."
        }
    }
}

private struct StatusLine: View {
    let symbol: String
    let text: String
    var isWorking = false
    var isProblem = false

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(isProblem ? AnyShapeStyle(Norm.Tone.warning.color) : AnyShapeStyle(.tint))
                .symbolEffect(.pulse, isActive: isWorking)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}

private struct MeasuringCard: View {
    let liveKg: Double?

    var body: some View {
        VStack(spacing: 8) {
            HeroNumber(liveKg.map { $0.formatted(digits: 2) } ?? "—", size: 72)
                .contentTransition(.numericText())
                .animation(.snappy, value: liveKg)
            Text("кг")
                .font(.title3)
                .foregroundStyle(.secondary)
            ProgressView()
                .padding(.top, 8)
            Text("Стій рівно й не рухайся: ваги міряють баланс, склад тіла і пульс.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

private struct UnassignedCard: View {
    let weighing: Weighing
    let people: [Person]

    var body: some View {
        Card(title: "Нове зважування") {
            HStack(alignment: .firstTextBaseline) {
                HeroNumber(weighing.weightKg.kg, size: 44)
                Spacer()
                Text(weighing.date.dayAndTime)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text("Чиє це зважування?")
                .font(.headline)
                .padding(.top, 8)
            Text("Ця вага не схожа на нікого зі списку або схожа одразу на кількох.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            AssignActions(weighing: weighing, people: people)
                .buttonStyle(.bordered)
            Explanation("Нову людину можна додати у вкладці «Люди».")
        }
    }
}

private struct JustWeighedCard: View {
    let weighing: Weighing
    let people: [Person]
    let history: [WeighingPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label {
                    Text("Збережено · \(weighing.date.formatted(date: .omitted, time: .shortened))")
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Norm.Tone.good.color)
                }
                .font(.subheadline.weight(.semibold))
                Spacer()
                if let person = weighing.person {
                    Menu("Не \(person.displayName)?") { AssignActions(weighing: weighing, people: people) }
                        .font(.subheadline)
                }
            }
            HeroNumber(weighing.weightKg.kg, size: 48)
            if let comparison = trendComparison {
                Text(comparison)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            let keyMetrics = weighing.metrics.filter(\.isKey)
            if !keyMetrics.isEmpty {
                Divider().padding(.vertical, 4)
                ForEach(keyMetrics) { MetricLine(row: $0) }
            }
            NavigationLink {
                WeighingDetailView(weighing: weighing)
            } label: {
                HStack(spacing: 4) {
                    Text("Усі показники")
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                }
                .font(.callout)
            }
            .padding(.top, 4)
        }
        .cardStyle()
    }

    private var trendComparison: String? {
        guard let deviation = WeightAnalysis.trendDeviation(of: weighing.point, history: history) else { return nil }
        func summary(_ difference: Double) -> String {
            "На \(abs(difference).kg) \(difference > 0 ? "вище" : "нижче") тренду."
        }
        return switch deviation {
        case .matches: "Збігається з трендом."
        case let .water(difference): "\(summary(difference)) Це звичайне коливання води."
        case let .food(difference): "\(summary(difference)) Таке буває після солоної їжі чи тренування. Дивись на тренд."
        case let .large(difference): summary(difference)
        }
    }
}

private struct TrendCard: View {
    let trend: [TrendPoint]
    let rate: Double?
    let forecast: GoalForecast

    var body: some View {
        Card(title: "Вага за трендом") {
            if let current = trend.last?.trendKg {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    HeroNumber(current.kg, size: 40)
                    if let rate {
                        Text("\(rate.signedKg)/тиж")
                            .font(.headline)
                            .monospacedDigit()
                            .foregroundStyle(rateTone.color)
                    }
                }
                let lastMonth = trend.suffix(30)
                if lastMonth.count > 1 {
                    Sparkline(points: Array(lastMonth))
                }
                Explanation(rate == nil
                    ? "Темп з'явиться, коли буде \(WeightAnalysis.minimumRateDays.daysText) зважувань за \(WeightAnalysis.minimumRateSpanDays.daysText)."
                    : "Тренд — середнє за \(WeightAnalysis.trendWindowDays.daysText): не стрибає від води та їжі. Темп — за \(WeightAnalysis.rateWindowDays.daysText).")
            } else {
                Explanation("Зважся хоча б раз, щоб побачити тренд.")
            }
        }
    }

    private var rateTone: Norm.Tone {
        switch forecast {
        case .eta: .good
        case .movingAway: .warning
        default: .neutral
        }
    }
}

private struct Sparkline: View {
    let points: [TrendPoint]

    var body: some View {
        VStack(spacing: 2) {
            Chart(points) { point in
                LineMark(x: .value("День", point.day, unit: .day), y: .value("Тренд", point.trendKg))
                    .foregroundStyle(ChartPalette.primary)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: domain)
            .frame(height: 48)
            HStack {
                Text(points.first?.day.shortDay ?? "")
                Spacer()
                Text(points.last?.day.shortDay ?? "")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .accessibilityHidden(true)
    }

    private var domain: ClosedRange<Double> {
        let values = points.map(\.trendKg)
        return ((values.min() ?? 0) - 0.2)...((values.max() ?? 1) + 0.2)
    }
}

private struct GoalCard: View {
    let goalKg: Double?
    let progress: GoalProgress?
    let forecast: GoalForecast

    var body: some View {
        if let goalKg {
            Card(title: "Шлях до цілі \(goalKg.kg)") {
                if let progress {
                    Text("Залишилось \(progress.remainingKg.kg)")
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                    ProgressView(value: progress.fraction)
                        .tint(ChartPalette.primary)
                    Text("Старт \(progress.startKg.kg) · пройдено \(max(progress.doneKg, 0).kg)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                let summary = summary
                Label(summary.text, systemImage: summary.symbol)
                    .font(.callout)
                    .padding(.top, 4)
            }
        } else {
            Card(title: "Ціль") {
                Explanation("Вкажи цільову вагу у вкладці «Люди», щоб бачити шлях до неї і прогноз.")
            }
        }
    }

    private var summary: (text: String, symbol: String) {
        switch forecast {
        case .noGoal:
            ("Вкажи цільову вагу в профілі.", "info.circle")
        case .reached:
            ("Ціль досягнуто.", "checkmark.circle")
        case .notEnoughData:
            ("Для прогнозу потрібні \(WeightAnalysis.minimumRateDays.daysText) зважувань за \(WeightAnalysis.minimumRateSpanDays.daysText).", "info.circle")
        case .movingAway:
            ("Зараз вага рухається від цілі.", "arrow.uturn.backward.circle")
        case .tooSlow:
            ("Вага майже не змінюється, тож дату не порахувати.", "info.circle")
        case let .eta(earliest, latest):
            ("Орієнтовно \(months(earliest, latest))", "calendar")
        }
    }

    private func months(_ earliest: Date, _ latest: Date) -> String {
        let calendar = Calendar.current
        let (first, last) = (earliest.formatted(.dateTime.month(.wide)), latest.formatted(.dateTime.month(.wide)))
        let (firstYear, lastYear) = (calendar.component(.year, from: earliest), calendar.component(.year, from: latest))
        if firstYear != lastYear { return "\(first) \(firstYear) – \(last) \(lastYear)" }
        return first == last ? "\(first) \(firstYear)" : "\(first)–\(last) \(firstYear)"
    }
}

private struct CompositionCard: View {
    let comparison: CompositionComparison?

    var body: some View {
        Card(title: "Склад тіла") {
            if let comparison {
                Text("За \(comparison.days.daysText): \(comparison.weightChangeKg.signedKg)")
                    .font(.headline)
                if comparison.fatChangeKg.sign == comparison.leanChangeKg.sign {
                    FatLeanBar(fatKg: abs(comparison.fatChangeKg), leanKg: abs(comparison.leanChangeKg))
                        .frame(height: 10)
                }
                Text("жир \(comparison.fatChangeKg.signedKg) · без жиру \(comparison.leanChangeKg.signedKg)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                let verdict = summary(WeightAnalysis.verdict(comparison))
                Label(verdict.text, systemImage: verdict.symbol)
                    .font(.callout)
                    .foregroundStyle(verdict.tone.color)
                    .padding(.top, 4)
                Explanation("Маса без жиру — це м'язи, вода, кістки й органи. Значення — середнє за \(WeightAnalysis.trendWindowDays.daysText).")
            } else {
                Explanation("Потрібні зважування з % жиру щонайменше за \(WeightAnalysis.compositionMinimumDays.daysText).")
            }
        }
    }

    private func summary(_ verdict: CompositionVerdict) -> (text: String, symbol: String, tone: Norm.Tone) {
        let advice = "Більше білка і силових тренувань допоможуть зберегти м'язи."
        return switch verdict {
        case let .losingMostlyFat(share):
            ("\(percent(share)) скинутого — жир. Це добре.", "checkmark.circle", .good)
        case let .losingMuchLean(share):
            ("Лише \(percent(share)) скинутого — жир. \(advice)", "exclamationmark.triangle", .warning)
        case .losingNoFat:
            ("Вага йде, а жир — ні. \(advice)", "exclamationmark.triangle", .warning)
        case let .gainingMostlyFat(share):
            ("\(percent(share)) набраного — жир.", "exclamationmark.triangle", .warning)
        case .gainingMostlyLean:
            ("Більша частина набраного — маса без жиру. Схоже на набір м'язів.", "checkmark.circle", .good)
        case .lessFatSameWeight:
            ("Вага стоїть, а жиру менше. Схоже на набір м'язів.", "checkmark.circle", .good)
        case .moreFatSameWeight:
            ("Вага стоїть, а жиру більше.", "exclamationmark.triangle", .warning)
        case .stable:
            ("Склад тіла стабільний.", "equal.circle", .neutral)
        }
    }

    private func percent(_ share: Double) -> String {
        "\((min(share, 1) * 100).formatted(digits: 0)) %"
    }
}

private struct LastWeighingRow: View {
    let weighing: Weighing
    @Environment(WeighingRecorder.self) private var recorder

    var body: some View {
        if !recorder.isJustFinished(weighing) {
            link
        }
    }

    private var link: some View {
        NavigationLink {
            WeighingDetailView(weighing: weighing)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Останнє зважування")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(weighing.date.dayAndTime)
                }
                Spacer()
                Text(weighing.weightKg.kg)
                    .font(.headline)
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .cardStyle()
        }
        .buttonStyle(.plain)
    }
}

private struct StreakLine: View {
    let days: Int

    var body: some View {
        if days >= 2 {
            Label("\(days.daysText) поспіль", systemImage: "flame")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
    }
}
