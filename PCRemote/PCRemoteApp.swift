import SwiftUI

@main
struct PCRemoteApp: App {
    @StateObject private var conn = RemoteConnection()
    @StateObject private var pad = GamepadManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(conn)
                .environmentObject(pad)
                .onAppear { pad.attach(to: conn) }
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var conn: RemoteConnection

    var body: some View {
        Group {
            if conn.status == .connected {
                MainTabView()
            } else {
                ConnectView()
            }
        }
        .onChange(of: conn.status) { status in
            // Tiene lo schermo acceso mentre si controlla il PC
            UIApplication.shared.isIdleTimerDisabled = (status == .connected)
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject var conn: RemoteConnection

    var body: some View {
        TabView {
            ControlView()
                .tabItem { Label("Controllo", systemImage: "computermouse") }
            KeyboardView()
                .tabItem { Label("Tastiera", systemImage: "keyboard") }
            CommandsView()
                .tabItem { Label("Comandi", systemImage: "power") }
            FilesView()
                .tabItem { Label("File", systemImage: "folder") }
            GamepadView()
                .tabItem { Label("Gamepad", systemImage: "gamecontroller") }
        }
        .overlay(alignment: .top) {
            if let msg = conn.toast {
                Text(msg)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: msg) {
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        conn.toast = nil
                    }
            }
        }
        .animation(.easeInOut, value: conn.toast)
    }
}
