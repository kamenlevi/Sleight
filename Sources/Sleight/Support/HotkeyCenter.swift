import Carbon.HIToolbox
import Foundation

/// Global hotkeys through Carbon's RegisterEventHotKey — the sanctioned API:
/// works without Accessibility or any permission, swallows the combination
/// system-wide, and survives rebuilds. Handles every shortcut except
/// Globe(fn) combos, which Carbon cannot express (those go through the
/// event tap instead).
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
    private var handlerInstalled = false
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
        installHandlerIfNeeded()

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
                GetEventDispatcherTarget(),
                0,
                &ref
            )
            if status == noErr, let ref {
                idMap[nextID] = entry.id
                registered.append(ref)
            }
            nextID += 1
        }
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ in
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
        }, 1, &eventType, nil, nil)
        handlerInstalled = true
    }

    private func fire(_ rawID: UInt32) {
        guard let id = idMap[rawID] else { return }
        onHotkey?(id)
    }
}
