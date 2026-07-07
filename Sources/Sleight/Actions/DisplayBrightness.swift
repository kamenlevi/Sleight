import CoreGraphics
import Foundation

/// Display brightness through the private DisplayServices framework, the same
/// mechanism the brightness keys use. Works on built-in and Apple displays.
enum DisplayBrightness {
    private typealias GetBrightnessF = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightnessF = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias CanChangeF = @convention(c) (CGDirectDisplayID) -> Bool

    private static let handle: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
        RTLD_NOW
    )

    private static let getBrightness: GetBrightnessF? = {
        guard let handle, let sym = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(sym, to: GetBrightnessF.self)
    }()

    private static let setBrightness: SetBrightnessF? = {
        guard let handle, let sym = dlsym(handle, "DisplayServicesSetBrightness") else { return nil }
        return unsafeBitCast(sym, to: SetBrightnessF.self)
    }()

    private static let canChange: CanChangeF? = {
        guard let handle, let sym = dlsym(handle, "DisplayServicesCanChangeBrightness") else { return nil }
        return unsafeBitCast(sym, to: CanChangeF.self)
    }()

    /// The first display whose brightness we can actually change.
    private static func targetDisplay() -> CGDirectDisplayID? {
        var displays = [CGDirectDisplayID](repeating: 0, count: 8)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(8, &displays, &count)
        let online = displays.prefix(Int(count))
        if let canChange {
            if let adjustable = online.first(where: { canChange($0) }) {
                return adjustable
            }
            return nil
        }
        return online.first ?? CGMainDisplayID()
    }

    static var isAvailable: Bool {
        getBrightness != nil && setBrightness != nil && targetDisplay() != nil
    }

    static func get() -> Float? {
        guard let getBrightness, let display = targetDisplay() else { return nil }
        var value: Float = 0
        guard getBrightness(display, &value) == 0 else { return nil }
        return value
    }

    static func set(_ value: Float) {
        guard let setBrightness, let display = targetDisplay() else { return }
        _ = setBrightness(display, min(max(value, 0), 1))
    }
}
