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
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        // .moveToActiveSpace (not .canJoinAllSpaces, which macOS doesn't
        // reliably honor for this panel): every orderFront pulls the HUD onto
        // the desktop the user is currently on.
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        panel.contentView = NSHostingView(rootView: HUDView(model: model))
        panel.alphaValue = 0
        return panel
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
