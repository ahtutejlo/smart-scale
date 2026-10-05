import SwiftData
import SwiftUI

struct AnalysisView: View {
    @Environment(ProfileStore.self) private var profile
    @Query private var weighings: [Weighing]

    init() {
        let start = Calendar.current.date(byAdding: .day, value: -WeightAnalysis.analysisHistoryDays, to: .now) ?? .distantPast
        _weighings = Query(filter: #Predicate<Weighing> { $0.date >= start }, sort: \.date)
    }

    var body: some View {
        let points = weighings.points(for: profile.userProfile)
        let trend = WeightAnalysis.dailyTrend(points)
        let rate = WeightAnalysis.weeklyRateKg(trend)

        ScrollView {
            VStack(spacing: 16) {
                TrendCard(trendKg: trend.last?.trendKg, weekChange: WeightAnalysis.change(trend, overDays: WeightAnalysis.trendWindowDays))
                PaceCard(
                    rate: rate,
                    forecast: WeightAnalysis.forecast(currentKg: trend.last?.trendKg, weeklyRateKg: rate, goalKg: profile.settings.goalWeightKg)
                )
                CompositionCard(change: WeightAnalysis.compositionChange(points))
            }
            .padding()
        }
        .navigationTitle("Аналіз")
    }
}

private struct TrendCard: View {
    let trendKg: Double?
    let weekChange: Double?

    var body: some View {
        Card(title: "Вага за трендом") {
            if let trendKg {
                HeroNumber(trendKg.kg, size: 40)
                if let weekChange {
                    Text("За \(WeightAnalysis.trendWindowDays) днів: \(weekChange.signedKg)")
                        .font(.callout)
                }
                Explanation("Це середнє за останні \(WeightAnalysis.trendWindowDays) днів. Воно не стрибає від води та їжі, тому краще показує, куди насправді рухається вага.")
            } else {
                Explanation("Зважся хоча б раз, щоб побачити тренд.")
            }
        }
    }
}

private struct PaceCard: View {
    let rate: Double?
    let forecast: GoalForecast

    var body: some View {
        Card(title: "Темп і прогноз") {
            if let rate {
                Text("\(rate.signedKg) на тиждень")
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
            }
            Label(summary.text, systemImage: summary.symbol)
                .font(.callout)
            Explanation("Темп рахується за останні \(WeightAnalysis.rateWindowDays) днів.")
        }
    }

    private var summary: (text: String, symbol: String) {
        switch forecast {
        case .noGoal:
            ("Вкажи цільову вагу в профілі, щоб побачити прогноз.", "info.circle")
        case .reached:
            ("Ціль досягнуто.", "checkmark.circle")
        case .notEnoughData:
            ("Для прогнозу потрібні щонайменше \(WeightAnalysis.minimumRateDays) дні зважувань за \(WeightAnalysis.minimumRateSpanDays) днів.", "info.circle")
        case .movingAway:
            ("Зараз вага рухається від цілі.", "arrow.uturn.backward.circle")
        case .tooSlow:
            ("Вага майже не змінюється, тож дату досягнення цілі не порахувати.", "info.circle")
        case let .eta(date, goalKg):
            ("Ціль \(goalKg.kg): орієнтовно \(date.formatted(.dateTime.day().month(.wide).year()))", "calendar")
        }
    }
}

private struct CompositionCard: View {
    let change: CompositionChange?

    var body: some View {
        Card(title: "Жир проти м'язів") {
            if let change {
                HStack(spacing: 24) {
                    MetricCell(title: "Жир", value: change.fatKg.signedKg)
                    MetricCell(title: "Суха маса", value: change.leanKg.signedKg)
                }
                let verdict = summary(WeightAnalysis.verdict(change))
                Label(verdict.text, systemImage: verdict.symbol)
                    .font(.callout)
                Explanation("Порівняння перших і останніх зважувань за \(change.days) днів. Побутові ваги помиляються в % жиру на кілька відсотків, тому дивись на напрям, а не на точне число.")
            } else {
                Explanation("Потрібні зважування з % жиру щонайменше за \(WeightAnalysis.minimumRateSpanDays) днів.")
            }
        }
    }

    private func summary(_ verdict: CompositionVerdict) -> (text: String, symbol: String) {
        switch verdict {
        case .losingFat:
            ("Худнеш за рахунок жиру, а м'язи тримаються.", "checkmark.circle")
        case .losingLean:
            ("Разом із жиром іде й суха маса. Більше білка і силових тренувань допоможуть зберегти м'язи.", "exclamationmark.triangle")
        case .gainingBoth:
            ("Ростуть і жир, і суха маса.", "arrow.up.circle")
        case .gainingFat:
            ("Жир росте.", "exclamationmark.triangle")
        case .gainingLean:
            ("Суха маса росте, а жир стоїть. Схоже на набір м'язів.", "checkmark.circle")
        case .stable:
            ("Склад тіла стабільний.", "equal.circle")
        }
    }
}
