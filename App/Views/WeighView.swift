import ScaleKit
import SwiftData
import SwiftUI

struct WeighView: View {
    @Environment(WeighingRecorder.self) private var recorder
    @Environment(ProfileStore.self) private var profile
    @Query(.newest(limit: 10)) private var recent: [Weighing]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if profile.isComplete {
                    status
                } else {
                    Card(title: "Спершу профіль") {
                        Text("Вкажи вік і зріст у вкладці «Профіль». Без них ваги не порахують склад тіла.")
                    }
                }
                if case let .finished(reading) = recorder.connection.state {
                    ResultCard(
                        title: "Результат",
                        reading: reading,
                        previous: recent.first { $0.date < reading.date.addingTimeInterval(-60) },
                        profile: profile.userProfile
                    )
                } else if let last = recent.first {
                    ResultCard(title: "Останнє зважування", reading: last.reading, previous: recent.dropFirst().first, profile: profile.userProfile)
                }
            }
            .padding()
        }
        .navigationTitle("Зважування")
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
    let reading: ScaleReading
    let previous: Weighing?
    let profile: UserProfile?

    var body: some View {
        Card(title: title) {
            HStack(alignment: .firstTextBaseline) {
                HeroNumber(reading.weightKg.kg, size: 44)
                Spacer()
                Text(reading.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let previous {
                Text("Від попереднього зважування: \((reading.weightKg - previous.weightKg).signedKg)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                ForEach(metrics, id: \.title) { MetricCell(title: $0.title, value: $0.value) }
            }
            .padding(.top, 8)
        }
    }

    private var metrics: [(title: String, value: String)] {
        let composition = reading.composition(for: profile)
        let rows: [(String, String?)] = [
            ("Жир", composition?.bodyFatPercent.percent),
            ("Суха маса", composition?.leanMassKg.kg),
            ("М'язи", composition?.musclePercent?.percent),
            ("Вода", composition?.waterPercent?.percent),
            ("Вісцеральний жир", composition?.visceralFat.map { $0.formatted(digits: 1) }),
            ("Кістки", composition?.boneMassKg?.kg),
            ("Базовий обмін", composition?.bmrKcal.map { "\($0) ккал" }),
            ("Метаболічний вік", composition?.metabolicAge.map { "\($0)" }),
            ("Пульс", reading.heartRate.map { "\($0) уд/хв" }),
            ("Баланс ліва / права", reading.leftLegPercent.map { "\(Int($0.rounded())) / \(Int((100 - $0).rounded())) %" }),
        ]
        return rows.compactMap { title, value in value.map { (title, $0) } }
    }
}
