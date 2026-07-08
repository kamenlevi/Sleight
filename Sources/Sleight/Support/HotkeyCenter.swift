import Carbon.HIToolbox
import Foundation

/// Global hotkeys through Carbon's RegisterEventHotKey — works without any
/// permission and swallows the combination system-wide. The event tap
/// watches the same shortcuts as a second, independent path (it needs
/// Accessibility but catches everything, including Globe combos);
/// GestureCoordinator deduplicates when both fire.
final class HotkeyCenter: @unchecked Sendable {
    static let shared = HotkeyCenter()

    struct Entry {
        let id: UUID
        let keyCode: Int
        let modifiers: Int
    }

    /// Fired on the main thread when a registered hotkey is pressed.
    var onHotkey: (@Sendable (UUID) -> Void)?

    private var registered: [EventHotKeyRef] = []
    private var idMap: [UInt32: UUID] = [:]
    private var nextID: UInt32 = 1
    private var handlersInstalled = false
    private let signature: OSType = 0x534C_4754 // 'SLGT'

    private init() {}

    /// Must be called on the main thread.
    func update(_ entries: [Entry]) {
        for ref in registered {
            UnregisterEventHotKey(ref)
        }
        registered = []
        idMap = [:]
        guard !entries.isEmpty else { return }
        installHandlersIfNeeded()

        for entry in entries {
            var carbonModifiers: UInt32 = 0
            if entry.modifiers & Keystrokes.cmd != 0 { carbonModifiers |= UInt32(cmdKey) }
            if entry.modifiers & Keystrokes.opt != 0 { carbonModifiers |= UInt32(optionKey) }
            if entry.modifiers & Keystrokes.ctrl != 0 { carbonModifiers |= UInt32(controlKey) }
            if entry.modifiers & Keystrokes.shift != 0 { carbonModifiers |= UInt32(shiftKey) }

            let hotKeyID = EventHotKeyID(signature: signature, id: nextID)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(entry.keyCode),
                carbonModifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &ref
            )
            SleightLog.log("hotkey register keyCode=\(entry.keyCode) mods=\(entry.modifiers) status=\(status)")
            if status == noErr, let ref {
                idMap[nextID] = entry.id
                registered.append(ref)
            }
            nextID += 1
        }
    }

    private func installHandlersIfNeeded() {
        guard !handlersInstalled else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handler: EventHandlerUPP = { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            HotkeyCenter.shared.fire(hotKeyID.id)
            return noErr
        }
        // Install on both plausible targets; which one receives hotkey
        // events varies with app type, and a duplicate delivery is handled
        // by the coordinator's dedupe.
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, nil)
        InstallEventHandler(GetEventDispatcherTarget(), handler, 1, &eventType, nil, nil)
        handlersInstalled = true
    }

    private func fire(_ rawID: UInt32) {
        guard let id = idMap[rawID] else { return }
        SleightLog.log("hotkey fired via Carbon (id \(rawID))")
        onHotkey?(id)
    }
}
