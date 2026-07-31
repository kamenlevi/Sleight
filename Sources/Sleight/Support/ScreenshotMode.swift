import AppKit
import SwiftUI

/// Renders the settings window to PNGs for the README and release posts:
///
///     Sleight.app/Contents/MacOS/Sleight --screenshot docs
///
/// The app draws its own interface into an offscreen bitmap, so this needs no
/// screen-recording permission. Nothing is written back to the config while
/// it's active — see `ConfigStore.scheduleSave()`.
@MainActor
enum ScreenshotMode {
    /// True while the app is rendering images rather than running.
    private(set) static var isActive = false

    /// The directory to write into, if `--screenshot <directory>` was passed.
    static func requestedDirectory() -> URL? {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--screenshot") else { return nil }
        let path = args.indices.contains(flag + 1) ? args[flag + 1] : "docs"
        isActive = true
        return URL(fileURLWithPath: path)
    }

    /// Two fingers resting on the pad, so the Visualizer shows what it looks
    /// like in use rather than an empty rectangle.
    private static let sampleTouches = [
        Touch(id: 1, x: 0.36, y: 0.62, size: 0.55),
        Touch(id: 2, x: 0.63, y: 0.38, size: 0.48),
    ]

    static func run(into directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // The dark interface is what the shots are wanted in.
        NSApp.appearance = NSAppearance(named: .darkAqua)
        stageDemoConfig()

        let shots: [(SettingsTab, String)] = [
            (.general, "general"),
            (.shortcuts, "shortcuts"),
            (.automation, "automation"),
            (.gestures, "gestures"),
            (.custom, "custom"),
            (.visualizer, "visualizer"),
        ]
        capture(shots, index: 0, into: directory)
    }

    /// A tidy, representative setup to photograph. Whatever is really in the
    /// config is left alone — `ConfigStore` refuses to save while this mode is
    /// active — so the images show the app in use rather than one machine's
    /// personal shortcuts and app paths.
    private static func stageDemoConfig() {
        var config = SleightConfig()
        config.twoFingerDial = DialConfig(enabled: true, control: .volume)
        config.threeFingerDial = DialConfig(enabled: true, control: .displayBrightness)
        config.slider = SliderConfig(enabled: true, control: .keyboardBrightness)
        config.threeFingerTap = TapConfig(action: .playPause)
        config.fourFingerTap = TapConfig(action: .keyboardBrightnessCycle)
        config.fiveFingerTap = TapConfig(action: .missionControl)
        config.shortcuts = [
            ShortcutBinding(keyCode: 49, modifiers: Keystrokes.opt,
                            action: .keyboardBrightnessCycle),
            ShortcutBinding(keyCode: 46, modifiers: Keystrokes.ctrl | Keystrokes.opt,
                            action: .micMuteToggle),
            ShortcutBinding(keyCode: 37, modifiers: Keystrokes.ctrl | Keystrokes.opt,
                            action: .lockScreen),
            ShortcutBinding(keyCode: 17, modifiers: Keystrokes.ctrl | Keystrokes.opt,
                            action: .cycleInputSource),
        ]
        config.automations = [
            Automation(action: .setKeyboardBrightness, level: 0.2, hour: 21, minute: 0),
            Automation(action: .mute, hour: 9, minute: 0, weekdays: [2, 3, 4, 5, 6]),
        ]

        // A posture a hand actually makes: thumb resting low and left as an
        // anchor, index and middle above it sweeping up together. The default
        // zone radius is wide enough that three fingers' zones overlap into a
        // mess, so these are tightened until they read as separate targets.
        var gesture = CustomGesture()
        gesture.name = "Thumb-hold sweep"
        var thumb = CustomFinger(x: 0.27, y: 0.15)
        thumb.radius = 0.13
        thumb.direction = .none
        var index = CustomFinger(x: 0.42, y: 0.52)
        index.radius = 0.13
        index.direction = .up
        var middle = CustomFinger(x: 0.58, y: 0.60)
        middle.radius = 0.13
        middle.direction = .up
        gesture.fingers = [thumb, index, middle]
        gesture.control = .displayBrightness
        config.customGestures = [gesture]

        ConfigStore.shared.config = config
    }

    private static func capture(_ shots: [(SettingsTab, String)], index: Int, into directory: URL) {
        guard index < shots.count else {
            print("done")
            NSApp.terminate(nil)
            return
        }
        let (tab, name) = shots[index]
        SettingsState.shared.selectedTab = tab
        let visualizer = VisualizerModel()
        visualizer.touches = sampleTouches

        capture(SettingsView(visualizerModel: visualizer),
                to: directory.appendingPathComponent("\(name).png")) {
            capture(shots, index: index + 1, into: directory)
        }
    }

    // MARK: - Rendering

    /// Draws a view through a real, key window so the AppKit-backed controls —
    /// switches, sliders, pickers — come out in their active accent colours
    /// instead of the greys AppKit uses for inactive windows. Then mats the
    /// result on a soft backdrop so it reads as a screenshot, not a raw slab.
    private static func capture(_ view: some View, to url: URL,
                                then next: @escaping () -> Void) {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)

        // A titled window, captured whole: the title bar and traffic lights
        // are what make the image read as a screenshot of an app rather than a
        // slab of interface.
        let window = KeyableWindow(contentRect: hosting.frame,
                                   styleMask: [.titled, .closable, .miniaturizable],
                                   backing: .buffered, defer: false)
        window.title = "Sleight"
        window.contentView = hosting
        window.backgroundColor = .windowBackgroundColor
        window.isOpaque = true
        window.ignoresMouseEvents = true
        window.appearance = NSAppearance(named: .darkAqua)
        // On screen (AppKit won't make an offscreen window key) but invisible.
        window.alphaValue = 0.01
        if let visible = NSScreen.main?.visibleFrame {
            window.setFrameOrigin(NSPoint(x: visible.minX + 20, y: visible.minY + 20))
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Let SwiftUI settle: layout, permission reads, the first timer tick.
        after(1.2) {
            window.setContentSize(hosting.fittingSize)
            hosting.layoutSubtreeIfNeeded()
            // Claim key status again just before the shot: a later capture in
            // the run would otherwise lose it as the previous window closed,
            // and its switches would draw grey.
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            after(0.5) {
                // The frame view above the content is what carries the title
                // bar; falling back to the content alone loses it.
                let target = hosting.superview ?? hosting
                print("captured \(url.lastPathComponent) \(target.bounds.size) key=\(window.isKeyWindow)")
                guard let shot = bitmap(of: target) else {
                    FileHandle.standardError.write(Data("could not create bitmap\n".utf8))
                    return next()
                }
                window.orderOut(nil)
                write(matted(shot), to: url)
                next()
            }
        }
    }

    /// A borderless window can't become key by default, and controls inside a
    /// window that isn't key draw in their inactive greys.
    private final class KeyableWindow: NSWindow {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
    }

    /// Renders the view's layer tree. `cacheDisplay(in:to:)` misses controls
    /// whose tint lives in private sublayers, so go through Core Animation.
    private static func bitmap(of view: NSView) -> NSImage? {
        let bounds = view.bounds
        let scale = view.window?.backingScaleFactor ?? 2
        guard let layer = view.layer,
              let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(bounds.width * scale), pixelsHigh: Int(bounds.height * scale),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        // Point size first: the context takes its scale from the rep's size.
        rep.size = bounds.size
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

        let cg = context.cgContext
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        // Core Animation draws top-down and the bitmap context is bottom-up, so
        // a flipped view (SwiftUI's hosting view) needs correcting. The window's
        // frame view — the one carrying the title bar — is not flipped, and
        // correcting that one would stand the screenshot on its head.
        if view.isFlipped {
            cg.translateBy(x: 0, y: bounds.height)
            cg.scaleBy(x: 1, y: -1)
        }
        layer.render(in: cg)
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }

    private static func after(_ seconds: Double, _ work: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            MainActor.assumeIsolated(work)
        }
    }

    /// Puts the window on a padded backdrop with rounded corners and a soft
    /// shadow, so the image looks like a screenshot rather than a raw slab.
    private static func matted(_ image: NSImage) -> NSImage {
        let inset: CGFloat = 34
        let size = NSSize(width: image.size.width + inset * 2,
                          height: image.size.height + inset * 2)
        let canvas = NSImage(size: size)
        canvas.lockFocusFlipped(false)

        NSGradient(colors: [NSColor(calibratedWhite: 0.16, alpha: 1),
                            NSColor(calibratedWhite: 0.09, alpha: 1)])?
            .draw(in: NSRect(origin: .zero, size: size), angle: -90)

        let frame = NSRect(x: inset, y: inset,
                           width: image.size.width, height: image.size.height)
        let rounded = NSBezierPath(roundedRect: frame, xRadius: 12, yRadius: 12)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 22
        shadow.shadowOffset = NSSize(width: 0, height: -8)
        shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.45)
        shadow.set()
        NSColor.windowBackgroundColor.setFill()
        rounded.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        rounded.addClip()
        image.draw(in: frame)
        NSGraphicsContext.restoreGraphicsState()

        canvas.unlockFocus()
        return canvas
    }

    private static func write(_ image: NSImage, to url: URL) {
        // Redraw at 2x so the PNG is retina-sharp.
        let pixels = NSSize(width: image.size.width * 2, height: image.size.height * 2)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(pixels.width), pixelsHigh: Int(pixels.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return }
        rep.size = image.size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
    }
}
