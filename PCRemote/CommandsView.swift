import SwiftUI

struct CommandItem: Identifiable {
    let id: String          // nome del comando sul server
    let title: String
    let icon: String
    let confirm: Bool
}

struct CommandsView: View {
    @EnvironmentObject var conn: RemoteConnection
    @State private var pending: CommandItem?

    private let power: [CommandItem] = [
        CommandItem(id: "lock", title: "Blocca", icon: "lock", confirm: false),
        CommandItem(id: "sleep", title: "Sospendi", icon: "moon", confirm: true),
        CommandItem(id: "hibernate", title: "Iberna", icon: "snowflake", confirm: true),
        CommandItem(id: "logoff", title: "Disconnetti utente", icon: "person.crop.circle.badge.xmark", confirm: true),
        CommandItem(id: "restart", title: "Riavvia", icon: "arrow.clockwise", confirm: true),
        CommandItem(id: "shutdown", title: "Spegni", icon: "power", confirm: true),
        CommandItem(id: "cancel", title: "Annulla spegnimento/riavvio", icon: "xmark.circle", confirm: false)
    ]

    var body: some View {
        NavigationStack {
            List {
                Section("Audio e media") {
                    HStack {
                        mediaButton("backward.fill", "prev")
                        mediaButton("playpause.fill", "play")
                        mediaButton("forward.fill", "next")
                        mediaButton("speaker.slash.fill", "mute")
                        mediaButton("speaker.minus.fill", "voldown")
                        mediaButton("speaker.plus.fill", "volup")
                    }
                    .buttonStyle(.bordered)
                }

                Section("Alimentazione") {
                    ForEach(power) { item in
                        Button {
                            if item.confirm { pending = item } else { conn.command(item.id) }
                        } label: {
                            Label(item.title, systemImage: item.icon)
                        }
                    }
                }

                Section("Programmi") {
                    if conn.apps.isEmpty {
                        Text("Nessun programma. Aggiungili in config.json sul PC.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(conn.apps.enumerated()), id: \.offset) { index, name in
                        Button {
                            conn.launchApp(index)
                            conn.toast = "Avvio: \(name)"
                        } label: {
                            Label(name, systemImage: "app")
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        conn.disconnect()
                    } label: {
                        Label("Disconnetti da \(conn.hostName.isEmpty ? "PC" : conn.hostName)",
                              systemImage: "xmark.circle")
                    }
                }
            }
            .navigationTitle("Comandi")
            .confirmationDialog(
                pending?.title ?? "",
                isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                titleVisibility: .visible,
                presenting: pending
            ) { item in
                Button(item.title, role: .destructive) { conn.command(item.id) }
                Button("Annulla", role: .cancel) {}
            } message: { _ in
                Text("Il comando verrà eseguito subito sul PC.")
            }
        }
    }

    private func mediaButton(_ icon: String, _ key: String) -> some View {
        Button { conn.key(key) } label: {
            Image(systemName: icon).frame(maxWidth: .infinity)
        }
    }
}
