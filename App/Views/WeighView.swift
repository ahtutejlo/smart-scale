import ScaleKit
import SwiftData
import SwiftUI

struct WeighView: View {
    @Environment(WeighingRecorder.self) private var recorder
    @Query(.newest(limit: 1)) private var latest: [Weighing]
    @Query private var people: [Person]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                status
                if people.owner?.userProfile == nil {
                    Card(title: "Спершу профіль") {
                        Text("Вкажи свій вік і зріст у вкладці «Люди». Без них ваги не порахують склад тіла.")
                    }
                }
                if let weighing = latest.first {
                    ResultCard(title: isJustFinished ? "Результат" : "Останнє зважування", weighing: weighing, people: people)
                }
            }
            .padding()
        }
        .navigationTitle("Зважування")
    }

    private var isJustFinished: Bool {
        if case .finished = recorder.connection.state { true } else { false }
    }

    @ViewBuilder
    private var status: some View {
        switch recorder.connection.state {
        case .idle, .searching:
            StatusCard(
                symbol: "scalemass",
                title: "Стань на ваги босоніж",
                detail: "Апка підключиться сама. Закрий Active Era, щоб вона не перехопила ваги.",
                isWorking: true
            )
        case .connecting:
            StatusCard(symbol: "antenna.radiowaves.left.and.right", title: "Підключаюся до ваг…", detail: nil, isWorking: true)
        case let .measuring(liveKg):
            MeasuringCard(liveKg: liveKg)
        case .finished:
            StatusCard(
                symbol: "checkmark.circle.fill",
                title: "Готово, зважування збережено",
                detail: "Можна зійти з ваг. Наступне зважування підхопиться саме.",
                isWorking: false
            )
        case let .bluetoothUnavailable(problem):
            StatusCard(symbol: "exclamationmark.triangle", title: "Bluetooth недоступний", detail: problem.explanation, isWorking: false)
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

private struct StatusCard: View {
    let symbol: String
    let title: String
    let detail: String?
    let isWorking: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.largeTitle)
                .foregroundStyle(.tint)
                .symbolEffect(.pulse, isActive: isWorking)
                .frame(width: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                if let detail {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .cardStyle()
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

private struct ResultCard: View {
    let title: String
    let weighing: Weighing
    let people: [Person]

    var body: some View {
        Card(title: title) {
            HStack(alignment: .firstTextBaseline) {
                HeroNumber(weighing.weightKg.kg, size: 44)
                Spacer()
                Text(weighing.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let person = weighing.person {
                HStack {
                    Label(person.displayName, systemImage: "person.fill")
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Menu("Змінити") { AssignActions(weighing: weighing, people: people) }
                        .font(.callout)
                }
                if let previous = previous(of: person) {
                    Text("Від попереднього зважування: \((weighing.weightKg - previous.weightKg).signedKg)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                    ForEach(metrics, id: \.title) { MetricCell(title: $0.title, value: $0.value) }
                }
                .padding(.top, 8)
            } else {
                WhoWasIt(weighing: weighing, people: people)
            }
        }
    }

    private func previous(of person: Person) -> Weighing? {
        let cutoff = weighing.date.addingTimeInterval(-60)
        return person.weighings.filter { $0.date < cutoff }.max { $0.date < $1.date }
    }

    private var metrics: [(title: String, value: String)] {
        let composition = weighing.composition
        let rows: [(String, String?)] = [
            ("Жир", composition?.bodyFatPercent.percent),
            ("Маса без жиру", composition?.leanMassKg.kg),
            ("М'язи", composition?.musclePercent?.percent),
            ("Вода", composition?.waterPercent?.percent),
            ("Вісцеральний жир", composition?.visceralFat.map { $0.formatted(digits: 1) }),
            ("Кістки", composition?.boneMassKg?.kg),
            ("Базовий обмін", composition?.bmrKcal.map { "\($0) ккал" }),
            ("Метаболічний вік", composition?.metabolicAge.map { "\($0)" }),
            ("Пульс", weighing.heartRate.map { "\($0) уд/хв" }),
            ("Баланс ліва / права", weighing.leftLegPercent.map { "\(Int($0.rounded())) / \(Int((100 - $0).rounded())) %" }),
        ]
        return rows.compactMap { title, value in value.map { (title, $0) } }
    }
}

private struct WhoWasIt: View {
    let weighing: Weighing
    let people: [Person]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Чиє це зважування?")
                .font(.headline)
            Text("Ця вага не схожа на нікого зі списку або схожа одразу на кількох.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            AssignActions(weighing: weighing, people: people)
                .buttonStyle(.bordered)
            Text("Нову людину можна додати у вкладці «Люди».")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }
}
