import SwiftUI

struct PersonPicker: View {
    let people: [Person]
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        if people.count > 1 {
            let current = people.selected(settings.settings.selectedPersonID)
            let selection = Binding<UUID?>(
                get: { current?.id },
                set: { settings.settings.selectedPersonID = $0 }
            )
            Menu {
                Picker("Людина", selection: selection) {
                    ForEach(people.ownerFirst()) { Text($0.displayName).tag(Optional($0.id)) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(current?.displayName ?? "Людина")
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                }
            }
        }
    }
}

struct AssignActions: View {
    let weighing: Weighing
    let people: [Person]
    var allowsDiscard = true
    @Environment(WeighingRecorder.self) private var recorder

    var body: some View {
        ForEach(people.ownerFirst()) { person in
            Button(person.displayName) { recorder.requestAssign(weighing, to: person) }
        }
        if allowsDiscard {
            Divider()
            Button("Гість, не зберігати", role: .destructive) { recorder.discard(weighing) }
        }
    }
}

extension View {
    func confirmsUnusualAssignment(_ recorder: WeighingRecorder) -> some View {
        let pending = recorder.pendingAssignment
        return alert(
            "Точно \(pending?.person.displayName ?? "")?",
            isPresented: Binding(get: { recorder.pendingAssignment != nil }, set: { if !$0 { recorder.cancelPendingAssignment() } }),
            presenting: pending
        ) { pending in
            Button("Так, це \(pending.person.displayName)") { recorder.confirmPendingAssignment() }
            Button("Скасувати", role: .cancel) { recorder.cancelPendingAssignment() }
        } message: { pending in
            let difference = pending.weighing.weightKg - pending.usualKg
            Text("Зважування \(pending.weighing.weightKg.kg) на \(abs(difference).kg) \(difference > 0 ? "більше" : "менше"), ніж зазвичай важить ця людина (\(pending.usualKg.kg)).")
        }
    }
}
