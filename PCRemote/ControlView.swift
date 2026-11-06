import SwiftUI

struct ControlView: View {
    @EnvironmentObject var conn: RemoteConnection
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("showScreen") private var showScreen = true
    @AppStorage("directTouch") private var directTouch = false
    @AppStorage("quality") private var quality = 1
    @AppStorage("sensitivity") private var sensitivity = 1.0
    @AppStorage("invertScroll") private var invertScroll = false
    @State private var monitor = 1
    @State private var showSettings = false

    // larghezza, qualità JPEG, fps
    private let profiles: [(w: Int, q: Int, fps: Int)] = [(640, 35, 10), (960, 50, 12), (1280, 65, 15)]

    var body: some View {
        VStack(spacing: 0) {
            topBar

            GeometryReader { geo in
                let direct = directTouch && showScreen && conn.frame != nil
                let size = surfaceSize(in: geo.size)

                ZStack {
                    Color.black
                    if showScreen, let frame = conn.frame {
                        Image(uiImage: frame)
                            .resizable()
                            .interpolation(.medium)
                    } else if showScreen {
                        ProgressView("In attesa dello schermo…")
                    } else {
                        Text("Modalità trackpad")
                            .foregroundStyle(.secondary)
                    }
                    TouchSurface(
                        direct: direct,
                        sensitivity: sensitivity,
                        scrollSign: invertScroll ? -1 : 1,
                        onMove: { conn.move(dx: $0, dy: $1) },
                        onAbs: { conn.abs(x: $0, y: $1) },
                        onClick: { conn.click($0) },
                        onButton: { conn.button($0, down: $1) },
                        onScroll: { conn.scroll(dx: $0, dy: $1) }
                    )
                }
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 8)

            bottomBar
        }
        .onAppear { applyStream() }
        .onDisappear { conn.stopStream() }
        .onChange(of: showScreen) { _ in applyStream() }
        .onChange(of: quality) { _ in applyStream() }
        .onChange(of: monitor) { _ in applyStream() }
        .onChange(of: scenePhase) { _ in applyStream() }
        .sheet(isPresented: $showSettings) { settingsSheet }
    }

    // MARK: Parti

    private var topBar: some View {
        HStack {
            Label(conn.hostName.isEmpty ? "PC" : conn.hostName, systemImage: "display")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Button { showScreen.toggle() } label: {
                Image(systemName: showScreen ? "eye" : "eye.slash")
            }
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button { conn.click("left") } label: {
                Text("Sinistro").frame(maxWidth: .infinity)
            }
            Button { conn.click("middle") } label: {
                Text("Centrale").frame(maxWidth: .infinity)
            }
            Button { conn.click("right") } label: {
                Text("Destro").frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .padding(12)
    }

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Section("Schermo") {
                    Toggle("Mostra lo schermo del PC", isOn: $showScreen)
                    Toggle("Tocco diretto (tocchi dove vuoi cliccare)", isOn: $directTouch)
                        .disabled(!showScreen)
                    Picker("Qualità", selection: $quality) {
                        Text("Bassa (più veloce)").tag(0)
                        Text("Media").tag(1)
                        Text("Alta").tag(2)
                    }
                    if conn.monitors.count > 1 {
                        Picker("Monitor", selection: $monitor) {
                            ForEach(conn.monitors) { m in
                                Text("Monitor \(m.id) (\(m.width)×\(m.height))").tag(m.id)
                            }
                        }
                    }
                }
                Section("Trackpad") {
                    VStack(alignment: .leading) {
                        Text("Sensibilità")
                        Slider(value: $sensitivity, in: 0.4...3.0)
                    }
                    Toggle("Inverti lo scorrimento", isOn: $invertScroll)
                }
                Section("Gesti") {
                    Text("Tocco: clic sinistro · Tocco con 2 dita: clic destro")
                    Text("2 dita che scorrono: scroll · Tieni premuto e trascina: trascina")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .navigationTitle("Impostazioni")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { showSettings = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Logica

    private func surfaceSize(in available: CGSize) -> CGSize {
        guard showScreen, let f = conn.frame, f.size.height > 0 else { return available }
        let aspect = f.size.width / f.size.height
        let w = min(available.width, available.height * aspect)
        return CGSize(width: w, height: w / aspect)
    }

    private func applyStream() {
        if showScreen && scenePhase == .active {
            let p = profiles[min(max(quality, 0), profiles.count - 1)]
            conn.startStream(width: p.w, quality: p.q, fps: p.fps, monitor: monitor)
        } else {
            conn.stopStream()
        }
    }
}
