import Foundation
import ObjectiveC

/// Keyboard backlight via the private CoreBrightness framework's
/// KeyboardBrightnessClient, the same path the F5/F6 keys take.
final class KeyboardBacklight {
    static let shared = KeyboardBacklight()

    private var client: NSObject?
    private var keyboardID: UInt64 = 1

    private init() {
        guard dlopen(
            "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness",
            RTLD_NOW
        ) != nil else { return }
        guard let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else { return }
        let instance = cls.init()

        let idsSelector = NSSelectorFromString("copyKeyboardBacklightIDs")
        if instance.responds(to: idsSelector),
           let ids = instance.perform(idsSelector)?.takeRetainedValue() as? [NSNumber],
           let first = ids.first {
            keyboardID = first.uint64Value
        }
        client = instance
    }

    var isAvailable: Bool {
        guard let client else { return false }
        return client.responds(to: NSSelectorFromString("setBrightness:forKeyboard:"))
    }

    func get() -> Float? {
        guard let client else { return nil }
        let selector = NSSelectorFromString("brightnessForKeyboard:")
        guard client.responds(to: selector), let method = class_getMethodImplementation(type(of: client), selector) else {
            return nil
        }
        typealias GetF = @convention(c) (AnyObject, Selector, UInt64) -> Float
        let fn = unsafeBitCast(method, to: GetF.self)
        return fn(client, selector, keyboardID)
    }

    func set(_ value: Float) {
        guard let client else { return }
        let selector = NSSelectorFromString("setBrightness:forKeyboard:")
        guard client.responds(to: selector), let method = class_getMethodImplementation(type(of: client), selector) else {
            return
        }
        typealias SetF = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool
        let fn = unsafeBitCast(method, to: SetF.self)
        _ = fn(client, selector, min(max(value, 0), 1), keyboardID)
    }
}
