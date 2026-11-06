import SwiftUI

struct ConnectView: View {
    @EnvironmentObject var conn: RemoteConnection
    @AppStorage("host") private var host = ""
    @AppStorage("portText") private var portText = "8765"
    @State private var pin = Keychain.get("pin") ?? ""

    private var busy: Bool {
        conn.status == .connecting || conn.status == .authenticating
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Indirizzo IP del PC", text: $host)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Porta", text: $portText)
                        .keyboardType(.numberPad)
                    SecureField("PIN (mostrato dal server)", text: $pin)
                        .keyboardType(.numberPad)
                } header: {
                    Text("Il tuo PC")
                } footer: {
                    Text("A casa usa l'IP locale (es. 192.168.1.20). Fuori casa usa l'IP Tailscale del PC (inizia con 100.).")
                }

                Section {
                    Button {
                        Keychain.set(pin, for: "pin")
                        conn.connect(host: host, port: Int(portText) ?? 8765, pin: pin)
                    } label: {
                        HStack {
                            Text("Connetti")
                            if busy { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(busy || host.isEmpty || pin.isEmpty)
                }

                if case .failed(let message) = conn.status {
                    Section {
                        Text(message).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("PC Remote")
        }
    }
}
