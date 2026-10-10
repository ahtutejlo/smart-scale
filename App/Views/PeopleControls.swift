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
    @Environment(WeighingRecorder.self) private var recorder

    var body: some View {
        ForEach(people.ownerFirst()) { person in
            Button(person.displayName) { recorder.assign(weighing, to: person) }
        }
        Divider()
        Button("Гість, не зберігати", role: .destructive) { recorder.discard(weighing) }
    }
}
