import ScaleKit
import SwiftData
import SwiftUI

struct PeopleView: View {
    @Environment(\.modelContext) private var context
    @Environment(SettingsStore.self) private var settings
    @Environment(WeighingRecorder.self) private var recorder
    @Query private var people: [Person]
    @State private var newPerson: Person?
    @State private var personToDelete: Person?

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                ForEach(people.ownerFirst()) { person in
                    NavigationLink {
                        PersonForm(person: person).navigationTitle(person.displayName)
                    } label: {
                        PersonRow(person: person)
                    }
                    .swipeActions {
                        if !person.isOwner {
                            Button("Видалити", role: .destructive) { personToDelete = person }
                        }
                    }
                }
                Button {
                    newPerson = Person(name: "")
                } label: {
                    Label("Додати людину", systemImage: "plus")
                }
            } header: {
                Text("Хто користується вагами")
            } footer: {
                Text("Апка сама визначає за вагою, чиє це зважування. Якщо не впевнена, спитає.")
            }

            Section {
                Toggle("Записувати мої зважування", isOn: $settings.settings.writesToHealth)
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
                VStack(alignment: .leading, spacing: 4) {
                    Text("В Apple Health потрапляють лише зважування власника телефона.")
                    if let message = recorder.healthMessage {
                        Text(message)
                    }
                }
            }
        }
        .navigationTitle("Люди")
        .sheet(item: $newPerson) { person in
            NavigationStack {
                PersonForm(person: person)
                    .navigationTitle("Нова людина")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Скасувати") { newPerson = nil }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Зберегти") {
                                context.insert(person)
                                newPerson = nil
                            }
                            .disabled(person.name.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
            }
        }
        .confirmationDialog(
            "Видалити \(personToDelete?.displayName ?? "")?",
            isPresented: Binding(get: { personToDelete != nil }, set: { if !$0 { personToDelete = nil } }),
            titleVisibility: .visible,
            presenting: personToDelete
        ) { person in
            Button("Видалити", role: .destructive) { context.delete(person) }
        } message: { _ in
            Text("Зважування цієї людини залишаться, але стануть «нічиїми»: їх можна буде віддати комусь іншому.")
        }
    }
}

private struct PersonRow: View {
    let person: Person

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(person.displayName)
                if person.isOwner {
                    Text("власник телефона").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(details).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var details: String {
        guard let profile = person.userProfile else { return "вкажи вік і зріст" }
        let latest = person.latestWeightKg.map { " · остання вага \($0.kg)" } ?? ""
        return "\(profile.age) р. · \(profile.heightCm) см\(latest)"
    }
}

private struct PersonForm: View {
    private enum Field {
        case name
        case age
        case height
        case goal
    }

    @Bindable var person: Person
    @FocusState private var focusedField: Field?

    var body: some View {
        Form {
            Section {
                TextField("Ім'я", text: $person.name)
                    .focused($focusedField, equals: .name)
                Picker("Стать", selection: $person.sex) {
                    Text("Чоловік").tag(UserProfile.Sex.male)
                    Text("Жінка").tag(UserProfile.Sex.female)
                }
                row("Вік", unit: "років") {
                    TextField("напр. 30", value: $person.age, format: .number)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .age)
                }
                row("Зріст", unit: "см") {
                    TextField("напр. 175", value: $person.heightCm, format: .number)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .height)
                }
                row("Цільова вага", unit: "кг") {
                    TextField("напр. 80", value: $person.goalWeightKg, format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .goal)
                }
            } footer: {
                Text("Ваги міряють лише опір тіла слабкому струму. Жир, м'язи й воду апка рахує з нього разом зі статтю, віком і зростом.")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            if focusedField != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { focusedField = nil }
                        .fontWeight(.semibold)
                }
            }
        }
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
