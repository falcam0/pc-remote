import Foundation
import SwiftUI
import CryptoKit
import Security

// MARK: - Modelli

struct MonitorInfo: Identifiable, Hashable {
    let id: Int
    let width: Int
    let height: Int
}

struct FSEntry: Identifiable, Hashable {
    let name: String
    let path: String
    let isDir: Bool
    let size: Int64
    var id: String { path }
}

struct DirectoryListing {
    var path: String?
    var title: String
    var parent: String?
    var entries: [FSEntry]
}

struct SharedFile: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - Keychain (per il PIN)

enum Keychain {
    private static func base(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "PCRemote",
            kSecAttrAccount as String: key
        ]
    }

    static func set(_ value: String, for key: String) {
        SecItemDelete(base(key) as CFDictionary)
        var item = base(key)
        item[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        var query = base(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Connessione

@MainActor
final class RemoteConnection: ObservableObject {
    enum Status: Equatable {
        case disconnected, connecting, authenticating, connected
        case failed(String)
    }

    @Published var status: Status = .disconnected
    @Published var hostName = ""
    @Published var frame: UIImage?
    @Published var monitors: [MonitorInfo] = []
    @Published var apps: [String] = []
    @Published var directory: DirectoryListing?
    @Published var padStatus: String?
    @Published var downloadedFile: SharedFile?
    @Published var toast: String?

    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var receiver: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var pin = ""
    private var pendingFileName: String?

    // MARK: Connessione

    func connect(host: String, port: Int, pin: String) {
        teardown()
        let h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !h.isEmpty, let url = URL(string: "ws://\(h):\(port)") else {
            status = .failed("Indirizzo non valido")
            return
        }
        self.pin = pin
        status = .connecting

        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 8
        let s = URLSession(configuration: cfg)
        let t = s.webSocketTask(with: url)
        t.maximumMessageSize = 64 * 1024 * 1024
        session = s
        task = t
        t.resume()

        receiver = Task { [weak self] in await self?.receiveLoop(t) }
        watchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard let self, !Task.isCancelled else { return }
            if self.status == .connecting || self.status == .authenticating {
                self.fail("Il PC non risponde. Controlla indirizzo, Wi-Fi/VPN e firewall.")
            }
        }
    }

    func disconnect() {
        teardown()
        status = .disconnected
    }

    private func fail(_ message: String) {
        teardown()
        status = .failed(message)
    }

    private func teardown() {
        receiver?.cancel()
        watchdog?.cancel()
        task?.cancel(with: .goingAway, reason: nil)
        session?.invalidateAndCancel()
        task = nil
        session = nil
        frame = nil
        apps = []
        directory = nil
        monitors = []
        padStatus = nil
    }

    // MARK: Ricezione

    private func receiveLoop(_ t: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let msg = try await t.receive()
                switch msg {
                case .string(let s): handleText(s)
                case .data(let d): await handleBinary(d)
                @unknown default: break
                }
            } catch {
                if task === t {
                    let wasConnected = (status == .connected)
                    fail(wasConnected ? "Connessione persa." : "Impossibile collegarsi: \(error.localizedDescription)")
                }
                return
            }
        }
    }

    private func handleText(_ s: String) {
        guard let data = s.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let t = obj["t"] as? String else { return }

        switch t {
        case "hello":
            guard let nonce = obj["nonce"] as? String else { return }
            hostName = obj["host"] as? String ?? ""
            status = .authenticating
            send(["t": "auth", "mac": hmacHex(nonce)])

        case "auth":
            if obj["ok"] as? Bool == true {
                monitors = (obj["monitors"] as? [[String: Any]] ?? []).compactMap { m in
                    guard let i = m["i"] as? Int, let w = m["w"] as? Int, let h = m["h"] as? Int else { return nil }
                    return MonitorInfo(id: i, width: w, height: h)
                }
                watchdog?.cancel()
                status = .connected
                send(["t": "apps"])
            } else {
                fail("PIN errato oppure troppi tentativi. Riprova tra un minuto.")
            }

        case "apps":
            apps = obj["apps"] as? [String] ?? []

        case "fs":
            let entries = (obj["entries"] as? [[String: Any]] ?? []).compactMap { e -> FSEntry? in
                guard let n = e["n"] as? String, let p = e["p"] as? String else { return nil }
                return FSEntry(name: n, path: p,
                               isDir: e["d"] as? Bool ?? false,
                               size: Int64(e["s"] as? Int ?? 0))
            }
            directory = DirectoryListing(path: obj["path"] as? String,
                                         title: obj["title"] as? String ?? "Cartelle",
                                         parent: obj["parent"] as? String,
                                         entries: entries)

        case "file":
            pendingFileName = obj["name"] as? String

        case "pad_status":
            padStatus = obj["msg"] as? String

        case "err":
            toast = obj["msg"] as? String ?? "Errore"

        default:
            break
        }
    }

    private func handleBinary(_ d: Data) async {
        guard let kind = d.first else { return }
        let payload = Data(d.dropFirst())
        switch kind {
        case 1:
            let image = await Task.detached(priority: .userInitiated) {
                UIImage(data: payload)?.preparingForDisplay()
            }.value
            if let image { frame = image }
        case 2:
            let name = URL(fileURLWithPath: pendingFileName ?? "file").lastPathComponent
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            do {
                try payload.write(to: url, options: .atomic)
                downloadedFile = SharedFile(url: url)
            } catch {
                toast = "Impossibile salvare il file"
            }
            pendingFileName = nil
        default:
            break
        }
    }

    private func hmacHex(_ nonce: String) -> String {
        let key = SymmetricKey(data: Data(pin.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(nonce.utf8), using: key)
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Invio

    func send(_ obj: [String: Any]) {
        guard let task,
              status == .connected || status == .authenticating,
              let data = try? JSONSerialization.data(withJSONObject: obj),
              let s = String(data: data, encoding: .utf8) else { return }
        task.send(.string(s)) { _ in }
    }

    // Mouse
    func move(dx: Int, dy: Int) { send(["t": "move", "dx": dx, "dy": dy]) }
    func abs(x: Double, y: Double) { send(["t": "abs", "x": x, "y": y]) }
    func click(_ button: String, count: Int = 1) { send(["t": "click", "b": button, "n": count]) }
    func button(_ button: String, down: Bool) { send(["t": down ? "down" : "up", "b": button]) }
    func scroll(dx: Int, dy: Int) { send(["t": "scroll", "dx": dx, "dy": dy]) }

    // Tastiera
    func key(_ name: String, _ action: String = "tap") { send(["t": "key", "k": name, "a": action]) }
    func hotkey(_ keys: [String]) { send(["t": "hotkey", "keys": keys]) }
    func type(_ text: String) { send(["t": "text", "s": text]) }

    // Schermo
    func startStream(width: Int, quality: Int, fps: Int, monitor: Int) {
        send(["t": "stream", "on": true, "w": width, "q": quality, "fps": fps, "mon": monitor])
    }
    func stopStream() { send(["t": "stream", "on": false]) }

    // Sistema e programmi
    func command(_ name: String) { send(["t": "cmd", "c": name]) }
    func launchApp(_ index: Int) { send(["t": "launch", "i": index]) }

    // File
    func listRoots() { send(["t": "fs_roots"]) }
    func list(_ path: String) { send(["t": "fs_list", "path": path]) }
    func openOnPC(_ path: String) { send(["t": "fs_open", "path": path]); toast = "Aperto sul PC" }
    func download(_ path: String) { send(["t": "fs_get", "path": path]); toast = "Download in corso…" }
}
