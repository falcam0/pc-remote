import Foundation
import GameController
import Combine

struct PadState: Equatable {
    var lx: Float = 0
    var ly: Float = 0
    var rx: Float = 0
    var ry: Float = 0
    var lt: Float = 0
    var rt: Float = 0
    var buttons: [String] = []
}

/// Legge un controller fisico collegato all'iPhone (Xbox, PlayStation, MFi...)
/// e ne inoltra lo stato al PC, dove diventa un gamepad Xbox 360 virtuale.
@MainActor
final class GamepadManager: ObservableObject {
    @Published var controllerName: String?
    @Published var state = PadState()
    @Published var forwarding = false {
        didSet { if forwarding != oldValue { forwardingChanged() } }
    }

    private weak var connection: RemoteConnection?
    private var controller: GCController?
    private var scheduled = false
    private var cancellables = Set<AnyCancellable>()

    func attach(to conn: RemoteConnection) {
        guard connection == nil else { return }
        connection = conn

        NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
            guard let c = note.object as? GCController else { return }
            Task { @MainActor in self?.use(c) }
        }
        NotificationCenter.default.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.lost() }
        }

        // Se ci si riconnette al PC con l'inoltro attivo, riapre il gamepad virtuale
        conn.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self, status == .connected, self.forwarding else { return }
                self.connection?.send(["t": "pad_open"])
                self.scheduleSend()
            }
            .store(in: &cancellables)

        if let existing = GCController.controllers().first { use(existing) }
    }

    // MARK: Controller

    private func use(_ c: GCController) {
        guard let gamepad = c.extendedGamepad else { return }
        controller = c
        controllerName = c.vendorName ?? "Controller"
        gamepad.valueChangedHandler = { [weak self] _, _ in
            Task { @MainActor in self?.scheduleSend() }
        }
        if forwarding {
            connection?.send(["t": "pad_open"])
            scheduleSend()
        }
    }

    private func lost() {
        controller = nil
        controllerName = nil
        state = PadState()
        if forwarding { connection?.send(["t": "pad", "b": [String]()]) }
    }

    private func forwardingChanged() {
        if forwarding {
            connection?.send(["t": "pad_open"])
            scheduleSend()
        } else {
            connection?.send(["t": "pad_close"])
        }
    }

    // MARK: Invio (massimo ~120 aggiornamenti al secondo)

    private func scheduleSend() {
        guard !scheduled else { return }
        scheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.008) { [weak self] in
            Task { @MainActor in
                self?.scheduled = false
                self?.sendState()
            }
        }
    }

    private func sendState() {
        guard let gp = controller?.extendedGamepad else { return }

        var pressed: [String] = []
        func add(_ on: Bool, _ name: String) { if on { pressed.append(name) } }

        add(gp.buttonA.isPressed, "a")
        add(gp.buttonB.isPressed, "b")
        add(gp.buttonX.isPressed, "x")
        add(gp.buttonY.isPressed, "y")
        add(gp.leftShoulder.isPressed, "lb")
        add(gp.rightShoulder.isPressed, "rb")
        add(gp.buttonMenu.isPressed, "start")
        add(gp.buttonOptions?.isPressed ?? false, "back")
        add(gp.leftThumbstickButton?.isPressed ?? false, "ls")
        add(gp.rightThumbstickButton?.isPressed ?? false, "rs")
        add(gp.buttonHome?.isPressed ?? false, "guide")
        add(gp.dpad.up.isPressed, "up")
        add(gp.dpad.down.isPressed, "down")
        add(gp.dpad.left.isPressed, "left")
        add(gp.dpad.right.isPressed, "right")

        let s = PadState(
            lx: gp.leftThumbstick.xAxis.value,
            ly: gp.leftThumbstick.yAxis.value,
            rx: gp.rightThumbstick.xAxis.value,
            ry: gp.rightThumbstick.yAxis.value,
            lt: gp.leftTrigger.value,
            rt: gp.rightTrigger.value,
            buttons: pressed
        )
        if s != state { state = s }

        guard forwarding else { return }
        connection?.send([
            "t": "pad",
            "lx": s.lx, "ly": s.ly, "rx": s.rx, "ry": s.ry,
            "lt": s.lt, "rt": s.rt,
            "b": s.buttons
        ])
    }
}
