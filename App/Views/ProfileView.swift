import ScaleKit
import SwiftUI

struct ProfileView: View {
    @Environment(ProfileStore.self) private var profile
    @Environment(WeighingRecorder.self) private var recorder

    var body: some View {
        @Bindable var profile = profile
        Form {
            Section {
                Picker("Стать", selection: $profile.settings.sex) {
                    Text("Чоловік").tag(UserProfile.Sex.male)
                    Text("Жінка").tag(UserProfile.Sex.female)
                }
                row("Вік", unit: "років") {
                    TextField("0", value: $profile.settings.age, format: .number).keyboardType(.numberPad)
                }
                row("Зріст", unit: "см") {
                    TextField("0", value: $profile.settings.heightCm, format: .number).keyboardType(.numberPad)
                }
                row("Цільова вага", unit: "кг") {
                    TextField("не задано", value: $profile.settings.goalWeightKg, format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.decimalPad)
                }
            } header: {
                Text("Про тебе")
            } footer: {
                Text("Ваги міряють лише опір тіла слабкому струму. Жир, м'язи й воду апка рахує з нього разом зі статтю, віком і зростом.")
            }

            Section {
                Toggle("Записувати нові зважування", isOn: $profile.settings.writesToHealth)
                Button {
                    Task { await recorder.importHealthHistory() }
                } label: {
                    HStack {
                        Text("Імпортувати історію")
                        if recorder.isImporting {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(recorder.isImporting)
            } header: {
                Text("Apple Health")
            } footer: {
                if let message = recorder.healthMessage {
                    Text(message)
                }
            }
        }
        .navigationTitle("Профіль")
    }

    private func row(_ title: String, unit: String, @ViewBuilder field: () -> some View) -> some View {
        LabeledContent(title) {
            HStack {
                field().multilineTextAlignment(.trailing)
                Text(unit).foregroundStyle(.secondary)
            }
        }
    }
}
