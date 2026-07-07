import AppKit

/// Posts the special NX system-defined key events so media actions behave
/// exactly like the hardware keys (including the native bezel where relevant).
enum MediaKeys {
    static let playPause: Int32 = 16 // NX_KEYTYPE_PLAY
    static let next: Int32 = 17      // NX_KEYTYPE_NEXT
    static let previous: Int32 = 18  // NX_KEYTYPE_PREVIOUS
    static let fast: Int32 = 19      // NX_KEYTYPE_FAST
    static let rewind: Int32 = 20    // NX_KEYTYPE_REWIND

    static func press(_ key: Int32) {
        post(key, down: true)
        post(key, down: false)
    }

    private static func post(_ key: Int32, down: Bool) {
        let flags: NSEvent.ModifierFlags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
        let data1 = Int((key << 16) | Int32((down ? 0x0A : 0x0B) << 8))
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        ) else { return }
        event.cgEvent?.post(tap: .cghidEventTap)
    }
}
