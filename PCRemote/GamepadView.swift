import SwiftUI

struct GamepadView: View {
    @EnvironmentObject var conn: RemoteConnection
    @EnvironmentObject var pad: GamepadManager

    var body: some View {
        NavigationStack {
            Form {
                Section("Controller sull'iPhone") {
                    if let name = pad.controllerName {
                        Label(name, systemImage: "gamecontroller.fill")
                    } else {
                        Text("Nessun controller collegato.")
                            .foregroundStyle(.secondary)
                        Text("Accoppia un controller Xbox, PlayStation o MFi da Impostazioni › Bluetooth, poi torna qui.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Toggle("Usa come gamepad sul PC", isOn: $pad.forwarding)
                    if pad.forwarding, let status = conn.padStatus {
                        Text(status).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Inoltro al PC")
                } footer: {
                    Text("Sul PC deve essere installato il driver ViGEmBus (vedi README). L'inoltro continua anche se cambi scheda.")
                }

                if pad.controllerName != nil {
                    Section("Anteprima") {
                        PadPreview(state: pad.state)
                    }
                }
            }
            .navigationTitle("Gamepad")
        }
    }
}

private struct PadPreview: View {
    let state: PadState

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 32) {
                stick(x: state.lx, y: state.ly)
                stick(x: state.rx, y: state.ry)
            }
            HStack {
                ProgressView("LT", value: Double(state.lt))
                ProgressView("RT", value: Double(state.rt))
            }
            Text(state.buttons.isEmpty ? "Nessun tasto premuto" : state.buttons.joined(separator: " · ").uppercased())
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private func stick(x: Float, y: Float) -> some View {
        ZStack {
            Circle().stroke(Color.secondary, lineWidth: 2)
            Circle()
                .fill(Color.accentColor)
                .frame(width: 18, height: 18)
                .offset(x: CGFloat(x) * 28, y: CGFloat(-y) * 28)
        }
        .frame(width: 70, height: 70)
    }
}
