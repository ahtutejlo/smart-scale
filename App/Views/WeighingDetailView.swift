import SwiftData
import SwiftUI

struct MetricRow: Identifiable {
    let title: String
    let value: String
    let isKey: Bool
    let norm: Norm?

    init(_ title: String, _ value: String, isKey: Bool = false, norm: Norm? = nil) {
        self.title = title
        self.value = value
        self.isKey = isKey
        self.norm = norm
    }

    var id: String { title }
}

extension Weighing {
    var metrics: [MetricRow] {
        let composition = composition
        let profile = person?.userProfile
        let rows: [MetricRow?] = [
            composition.map { body in
                MetricRow("Жир", body.bodyFatPercent.percent, isKey: true, norm: profile.map { BodyNorms.bodyFat(body.bodyFatPercent, age: $0.age, sex: $0.sex) })
            },
            composition.map { MetricRow("Маса без жиру", $0.leanMassKg.kg) },
            composition?.musclePercent.map { MetricRow("М'язи", $0.percent) },
            composition?.waterPercent.map { water in
                MetricRow("Вода", water.percent, isKey: true, norm: profile.map { BodyNorms.water(water, sex: $0.sex) })
            },
            composition?.visceralFat.map { MetricRow("Вісцеральний жир", $0.formatted(digits: 1), isKey: true, norm: BodyNorms.visceralFat($0)) },
            composition?.boneMassKg.map { MetricRow("Кістки", $0.kg) },
            composition?.bmrKcal.map { MetricRow("Базовий обмін", "\($0) ккал") },
            composition?.metabolicAge.map { MetricRow("Метаболічний вік", "\($0)") },
            heartRate.map { MetricRow("Пульс", "\($0) уд/хв", isKey: true, norm: BodyNorms.heartRate($0)) },
            leftLegPercent.map { MetricRow("Баланс ліва / права", "\(Int($0.rounded())) / \(Int((100 - $0).rounded())) %") },
        ]
        return rows.compactMap { $0 }
    }

    var sourceLabel: (symbol: String, text: String) {
        switch source {
        case .scale: ("scalemass", "З ваг")
        case .scaleMemory: ("memorychip", "З пам'яті ваг")
        case .appleHealth: ("heart.text.square", "З Apple Health")
        }
    }
}

struct MetricLine: View {
    let row: MetricRow

    var body: some View {
        HStack(spacing: 8) {
            Text(row.title)
            Text(row.value)
                .fontWeight(.semibold)
                .monospacedDigit()
            Spacer(minLength: 8)
            if let norm = row.norm {
                NormChip(norm: norm)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct WeighingDetailView: View {
    let weighing: Weighing
    @Query private var people: [Person]

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HeroNumber(weighing.weightKg.kg, size: 44)
                    Text(weighing.date.formatted(date: .complete, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Чиє") {
                    Menu(weighing.person?.displayName ?? "Нічиє") {
                        AssignActions(weighing: weighing, people: people, allowsDiscard: false)
                    }
                }
            }
            Section {
                ForEach(weighing.metrics) { MetricLine(row: $0) }
            } header: {
                Text("Показники")
            } footer: {
                Text("Норми взято із загальних таблиць за віком і статтю. Побутові ваги помиляються в % жиру на кілька відсотків, тому дивись на напрям, а не на точне число.")
            }
            Section {
                Label(weighing.sourceLabel.text, systemImage: weighing.sourceLabel.symbol)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(weighing.date.dayAndTime)
        .navigationBarTitleDisplayMode(.inline)
    }
}
