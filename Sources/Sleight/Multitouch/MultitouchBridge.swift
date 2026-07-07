import Foundation
import CMultitouch

/// Runtime bridge to Apple's private MultitouchSupport.framework, loaded
/// with dlopen/dlsym so we never link against it at build time.
enum MultitouchBridge {
    typealias MTDeviceRef = UnsafeMutableRawPointer
    typealias ContactCallback = @convention(c) (
        MTDeviceRef?, UnsafeMutablePointer<MTTouch>?, Int32, Double, Int32
    ) -> Int32

    private typealias CreateListF = @convention(c) () -> Unmanaged<CFMutableArray>?
    private typealias RegisterCallbackF = @convention(c) (MTDeviceRef, ContactCallback) -> Void
    private typealias UnregisterCallbackF = @convention(c) (MTDeviceRef, ContactCallback) -> Void
    private typealias DeviceStartF = @convention(c) (MTDeviceRef, Int32) -> Int32
    private typealias DeviceStopF = @convention(c) (MTDeviceRef) -> Void
    private typealias DeviceIsRunningF = @convention(c) (MTDeviceRef) -> Bool
    private typealias DeviceIsBuiltInF = @convention(c) (MTDeviceRef) -> Bool

    private static let handle: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",
        RTLD_NOW
    )

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let sym = dlsym(handle, name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }

    private static let createList = symbol("MTDeviceCreateList", as: CreateListF.self)
    private static let registerCallback = symbol("MTRegisterContactFrameCallback", as: RegisterCallbackF.self)
    private static let unregisterCallback = symbol("MTUnregisterContactFrameCallback", as: UnregisterCallbackF.self)
    private static let deviceStart = symbol("MTDeviceStart", as: DeviceStartF.self)
    private static let deviceStop = symbol("MTDeviceStop", as: DeviceStopF.self)
    private static let deviceIsRunning = symbol("MTDeviceIsRunning", as: DeviceIsRunningF.self)
    private static let deviceIsBuiltIn = symbol("MTDeviceIsBuiltIn", as: DeviceIsBuiltInF.self)

    static var isAvailable: Bool {
        handle != nil && createList != nil && registerCallback != nil && deviceStart != nil
    }

    /// The returned array OWNS the device references — keep it alive for as
    /// long as any MTDeviceRef from it is in use, or MTDeviceStop will crash
    /// on a dangling pointer.
    static func deviceList() -> (owner: CFArray, devices: [MTDeviceRef])? {
        guard let createList, let array = createList()?.takeRetainedValue() else { return nil }
        let count = CFArrayGetCount(array)
        var devices: [MTDeviceRef] = []
        for i in 0..<count {
            if let ptr = CFArrayGetValueAtIndex(array, i) {
                devices.append(MTDeviceRef(mutating: ptr))
            }
        }
        return (array, devices)
    }

    static func register(_ device: MTDeviceRef, callback: ContactCallback) {
        registerCallback?(device, callback)
    }

    static func unregister(_ device: MTDeviceRef, callback: ContactCallback) {
        unregisterCallback?(device, callback)
    }

    @discardableResult
    static func start(_ device: MTDeviceRef) -> Bool {
        guard let deviceStart else { return false }
        return deviceStart(device, 0) == 0
    }

    static func stop(_ device: MTDeviceRef) {
        deviceStop?(device)
    }

    static func isRunning(_ device: MTDeviceRef) -> Bool {
        deviceIsRunning?(device) ?? false
    }

    static func isBuiltIn(_ device: MTDeviceRef) -> Bool {
        deviceIsBuiltIn?(device) ?? false
    }
}
