import SwiftUI
import UIKit

/// Superficie touch: 1 dito = muovi, tap = clic sinistro, tap con 2 dita = clic destro,
/// 2 dita che scorrono = scroll, tieni premuto e trascina = trascinamento.
struct TouchSurface: UIViewRepresentable {
    var direct: Bool                       // true: la posizione del dito = posizione sullo schermo del PC
    var sensitivity: Double
    var scrollSign: Double                 // 1 = scorrimento naturale, -1 = invertito
    var onMove: (Int, Int) -> Void
    var onAbs: (Double, Double) -> Void
    var onClick: (String) -> Void
    var onButton: (String, Bool) -> Void
    var onScroll: (Int, Int) -> Void

    func makeUIView(context: Context) -> TouchView {
        let v = TouchView()
        v.parent = self
        return v
    }

    func updateUIView(_ uiView: TouchView, context: Context) {
        uiView.parent = self
    }
}

final class TouchView: UIView, UIGestureRecognizerDelegate {
    var parent: TouchSurface!

    private var pendingMove = CGPoint.zero
    private var scrollAcc = CGPoint.zero
    private var lastFlush = CACurrentMediaTime()
    private var dragging = false
    private var lastLong = CGPoint.zero
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = true

        let tap = UITapGestureRecognizer(target: self, action: #selector(onTap(_:)))

        let tap2 = UITapGestureRecognizer(target: self, action: #selector(onTwoFingerTap(_:)))
        tap2.numberOfTouchesRequired = 2

        let pan = UIPanGestureRecognizer(target: self, action: #selector(onPan(_:)))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1

        let scroll = UIPanGestureRecognizer(target: self, action: #selector(onScrollPan(_:)))
        scroll.minimumNumberOfTouches = 2
        scroll.maximumNumberOfTouches = 2

        let long = UILongPressGestureRecognizer(target: self, action: #selector(onLong(_:)))
        long.minimumPressDuration = 0.35
        long.allowableMovement = 8

        for g in [tap, tap2, pan, scroll, long] as [UIGestureRecognizer] {
            g.delegate = self
            addGestureRecognizer(g)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non supportato") }

    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // Tap e pressione lunga sono mutuamente esclusivi (evita il doppio clic)
        let tapAndLong = (g is UITapGestureRecognizer && other is UILongPressGestureRecognizer)
            || (g is UILongPressGestureRecognizer && other is UITapGestureRecognizer)
        return !tapAndLong
    }

    // MARK: Helpers

    private func sendAbs(_ p: CGPoint) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        parent.onAbs(Double(min(max(p.x / bounds.width, 0), 1)),
                     Double(min(max(p.y / bounds.height, 0), 1)))
    }

    private func addMove(_ dx: CGFloat, _ dy: CGFloat) {
        let speed = Double(hypot(dx, dy))
        let gain = CGFloat(parent.sensitivity * (1 + min(speed / 20.0, 2.0)))
        pendingMove.x += dx * gain
        pendingMove.y += dy * gain
        flushMove(force: false)
    }

    private func flushMove(force: Bool) {
        let now = CACurrentMediaTime()
        guard force || now - lastFlush >= 0.016 else { return }
        let ix = Int(pendingMove.x.rounded(.towardZero))
        let iy = Int(pendingMove.y.rounded(.towardZero))
        if ix != 0 || iy != 0 {
            parent.onMove(ix, iy)
            pendingMove.x -= CGFloat(ix)
            pendingMove.y -= CGFloat(iy)
        }
        lastFlush = now
    }

    // MARK: Gesti

    @objc private func onTap(_ g: UITapGestureRecognizer) {
        if parent.direct { sendAbs(g.location(in: self)) }
        haptic.impactOccurred()
        parent.onClick("left")
    }

    @objc private func onTwoFingerTap(_ g: UITapGestureRecognizer) {
        if parent.direct { sendAbs(g.location(in: self)) }
        haptic.impactOccurred()
        parent.onClick("right")
    }

    @objc private func onPan(_ g: UIPanGestureRecognizer) {
        if dragging { return }
        switch g.state {
        case .began, .changed:
            if parent.direct {
                sendAbs(g.location(in: self))
            } else {
                let t = g.translation(in: self)
                g.setTranslation(.zero, in: self)
                addMove(t.x, t.y)
            }
        case .ended, .cancelled, .failed:
            flushMove(force: true)
        default:
            break
        }
    }

    @objc private func onScrollPan(_ g: UIPanGestureRecognizer) {
        switch g.state {
        case .began, .changed:
            let t = g.translation(in: self)
            g.setTranslation(.zero, in: self)
            scrollAcc.x += t.x / 14
            scrollAcc.y += t.y / 14
            let ix = Int(scrollAcc.x.rounded(.towardZero))
            let iy = Int(scrollAcc.y.rounded(.towardZero))
            if ix != 0 || iy != 0 {
                scrollAcc.x -= CGFloat(ix)
                scrollAcc.y -= CGFloat(iy)
                let sign = parent.scrollSign
                // dita in giù = contenuto in giù = scroll verso l'alto (naturale)
                parent.onScroll(-Int(Double(ix) * sign), Int(Double(iy) * sign))
            }
        case .ended, .cancelled, .failed:
            scrollAcc = .zero
        default:
            break
        }
    }

    @objc private func onLong(_ g: UILongPressGestureRecognizer) {
        switch g.state {
        case .began:
            dragging = true
            haptic.impactOccurred()
            lastLong = g.location(in: self)
            if parent.direct { sendAbs(lastLong) }
            parent.onButton("left", true)
        case .changed:
            guard dragging else { return }
            let p = g.location(in: self)
            if parent.direct {
                sendAbs(p)
            } else {
                addMove(p.x - lastLong.x, p.y - lastLong.y)
                lastLong = p
            }
        case .ended, .cancelled, .failed:
            if dragging {
                flushMove(force: true)
                parent.onButton("left", false)
                dragging = false
            }
        default:
            break
        }
    }
}
