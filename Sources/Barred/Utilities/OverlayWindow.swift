import AppKit

final class OverlayWindow: NSPanel {
    private let effectView: NSVisualEffectView

    init() {
        effectView = NSVisualEffectView()
        effectView.material = .menu
        effectView.blendingMode = .behindWindow
        effectView.state = .active

        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = false
        contentView = effectView
    }

    func cover(frame: CGRect) {
        setFrame(frame, display: true)
        orderFrontRegardless()
    }

    func animateReveal(to newFrame: CGRect, duration: TimeInterval = 0.25) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().setFrame(newFrame, display: true)
        }
    }

    func hide() {
        orderOut(nil)
    }
}
