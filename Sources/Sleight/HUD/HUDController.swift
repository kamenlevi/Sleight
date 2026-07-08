import AppKit
import SwiftUI

@MainActor
@Observable
final class HUDModel {
    var control: ContinuousControl = .volume
    var value: Float = 0
    var available = true
    var muted = false
}

/// Floating feedback bezel shown while a dial gesture is adjusting something.
/// Non-activating, click-through, visible over full-screen apps.
@MainActor
final class HUDController {
    static let shared = HUDController()

    let model = HUDModel()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?
    /// Bumped on every show; a scheduled hide only applies if no newer show
    /// happened, so rapid re-triggering right after a fade can't be eaten by
    /// the stale fade-out's completion.
    private var generation = 0

    private init() {}

    private func makePanel() -> NSPanel {
        let size = NSSize(width: 280, height: 58)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        // .moveToActiveSpace (not .canJoinAllSpaces, which macOS doesn't
        // reliably honor for this panel): every orderFront pulls the HUD onto
        // the desktop the user is currently on.
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]

        // The bezel background is a native visual-effect view masked to a
        // capsule — the same construction as the system volume HUD. SwiftUI
        // materials render their glass backing against the window's
        // rectangular bounds on current macOS, which showed as a boxy
        // outline around the capsule.
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        let effect = NSVisualEffectView(frame: container.bounds)
        effect.autoresizingMask = [.width, .height]
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = Self.capsuleMask(size: size)
        container.addSubview(effect)

        let hosting = NSHostingView(rootView: HUDView(model: model))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)

        panel.contentView = container
        panel.alphaValue = 0
        return panel
    }

    private static func capsuleMask(size: NSSize) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(
                roundedRect: rect,
                xRadius: rect.height / 2,
                yRadius: rect.height / 2
            ).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(
            top: size.height / 2, left: size.height / 2,
            bottom: size.height / 2, right: size.height / 2
        )
        return image
    }

    func show(control: ContinuousControl, value: Float, available: Bool, muted: Bool = false) {
        hideTask?.cancel()
        hideTask = nil
        generation += 1

        model.control = control
        model.value = value
        model.available = available
        model.muted = muted

        let panel = self.panel ?? makePanel()
        self.panel = panel

        // Show on the screen the user is actually looking at — the one with
        // the pointer — never a previous display or Space.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        if let screen {
            let frame = screen.visibleFrame
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.minY + frame.height * 0.12
            ))
        }

        panel.orderFrontRegardless()
        if panel.alphaValue < 1 {
            // Animate up from wherever a possible in-flight fade left it.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
        }
    }

    func update(control: ContinuousControl, value: Float) {
        guard panel?.isVisible == true else {
            show(control: control, value: value, available: true)
            return
        }
        hideTask?.cancel()
        hideTask = nil
        model.control = control
        model.value = value
        model.muted = false
    }

    func scheduleHide(after seconds: Double = 0.9) {
        hideTask?.cancel()
        let scheduledGeneration = generation
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, let panel = self.panel,
                  scheduledGeneration == self.generation else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.35
                panel.animator().alphaValue = 0
            }, completionHandler: {
                // Animation completions arrive on the main thread.
                MainActor.assumeIsolated {
                    HUDController.shared.finishHide(ifGeneration: scheduledGeneration)
                }
            })
        }
    }

    private func finishHide(ifGeneration scheduled: Int) {
        guard scheduled == generation else { return }
        panel?.orderOut(nil)
    }
}
