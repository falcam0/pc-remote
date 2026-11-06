import SwiftUI
import UIKit

// MARK: - Campo invisibile che cattura la tastiera di iOS

final class CaptureField: UITextField {
    var onText: ((String) -> Void)?
    var onBackspace: (() -> Void)?
    var onResign: (() -> Void)?

    override func insertText(_ text: String) { onText?(text) }
    override func deleteBackward() { onBackspace?() }
    override func caretRect(for position: UITextPosition) -> CGRect { .zero }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        onResign?()
        return result
    }
}

struct KeyCapture: UIViewRepresentable {
    @Binding var active: Bool
    var onText: (String) -> Void
    var onBackspace: () -> Void

    func makeUIView(context: Context) -> CaptureField {
        let f = CaptureField()
        f.autocorrectionType = .no
        f.autocapitalizationType = .none
        f.spellCheckingType = .no
        f.smartQuotesType = .no
        f.smartDashesType = .no
        f.smartInsertDeleteType = .no
        f.alpha = 0.02
        return f
    }

    func updateUIView(_ f: CaptureField, context: Context) {
        f.onText = onText
        f.onBackspace = onBackspace
        let binding = $active
        f.onResign = { DispatchQueue.main.async { binding.wrappedValue = false } }
        if active, !f.isFirstResponder {
            DispatchQueue.main.async { f.becomeFirstResponder() }
        } else if !active, f.isFirstResponder {
            DispatchQueue.main.async { f.resignFirstResponder() }
        }
    }
}

// MARK: - Schermata tastiera

struct KeyboardView: View {
    @EnvironmentObject var conn: RemoteConnection
    @State private var live = false
    @State private var text = ""
    @State private var mods: Set<String> = []

    private let columns = [GridItem(.adaptive(minimum: 64), spacing: 8)]

    private let navKeys: [(String, String)] = [
        ("Esc", "esc"), ("Tab", "tab"), ("Invio", "enter"), ("⌫", "backspace"), ("Canc", "delete"),
        ("Home", "home"), ("Fine", "end"), ("Pag↑", "pageup"), ("Pag↓", "pagedown"),
        ("←", "left"), ("↑", "up"), ("↓", "down"), ("→", "right"), ("Spazio", "space")
    ]

    private let shortcuts: [(String, [String])] = [
        ("Copia", ["ctrl", "c"]), ("Incolla", ["ctrl", "v"]), ("Taglia", ["ctrl", "x"]),
        ("Annulla", ["ctrl", "z"]), ("Tutto", ["ctrl", "a"]), ("Salva", ["ctrl", "s"]),
        ("Alt+Tab", ["alt", "tab"]), ("Desktop", ["win", "d"]), ("Chiudi", ["alt", "f4"]),
        ("Task Mgr", ["ctrl", "shift", "esc"]), ("Cattura", ["win", "shift", "s"]), ("Start", ["win"])
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    section("Digitazione") {
                        Button {
                            live.toggle()
                        } label: {
                            Label(live ? "Chiudi la tastiera live" : "Tastiera live (scrivi direttamente sul PC)",
                                  systemImage: "keyboard")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        HStack {
                            TextField("Oppure scrivi qui e invia", text: $text)
                                .textFieldStyle(.roundedBorder)
                                .submitLabel(.send)
                                .onSubmit(sendText)
                            Button("Invia", action: sendText)
                                .buttonStyle(.bordered)
                                .disabled(text.isEmpty)
                        }
                    }

                    section("Modificatori (restano premuti)") {
                        LazyVGrid(columns: columns, spacing: 8) {
                            modifier("Ctrl", "ctrl")
                            modifier("Alt", "alt")
                            modifier("Maiusc", "shift")
                            modifier("Win", "win")
                        }
                    }

                    section("Tasti") {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(navKeys, id: \.1) { item in
                                Button(item.0) { conn.key(item.1) }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }

                    section("Tasti funzione") {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(1...12, id: \.self) { n in
                                Button("F\(n)") { conn.key("f\(n)") }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }

                    section("Scorciatoie") {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(shortcuts, id: \.0) { item in
                                Button(item.0) { conn.hotkey(item.1) }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Tastiera")
            .background(
                KeyCapture(active: $live,
                           onText: { conn.type($0) },
                           onBackspace: { conn.key("backspace") })
                    .frame(width: 1, height: 1)
            )
            .onDisappear {
                live = false
                for m in mods { conn.key(m, "up") }
                mods.removeAll()
            }
        }
    }

    // MARK: Componenti

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
    }

    private func modifier(_ label: String, _ name: String) -> some View {
        let on = mods.contains(name)
        return Button(label) {
            if on {
                mods.remove(name)
                conn.key(name, "up")
            } else {
                mods.insert(name)
                conn.key(name, "down")
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(on ? .orange : .gray)
    }

    private func sendText() {
        guard !text.isEmpty else { return }
        conn.type(text)
        text = ""
    }
}
