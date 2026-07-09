import AppKit
import CMultitouch
import Foundation

/// A single finger contact in normalized trackpad coordinates
/// (origin bottom-left, x and y in 0...1).
struct Touch: Identifiable, Hashable {
    let id: Int32
    let x: Float
    let y: Float
    let size: Float

    var point: SIMD2<Float> { SIMD2(x, y) }
}

struct TouchFrame {
    let deviceID: UInt
    let timestamp: Double
    let touches: [Touch]
}

/// Owns discovery and lifecycle of multitouch devices and fans their contact
/// frames out to a handler. Handles Bluetooth trackpads coming and going.
final class TouchStream {
    static let shared = TouchStream()

    /// Called on a private serial queue with every touch frame.
    var onFrame: ((TouchFrame) -> Void)?

    private(set) var deviceCount = 0
    /// Whether Input Monitoring was already granted when devices were last
    /// started; a grant does not apply retroactively, so the app restarts
    /// the stream when this flips.
    private(set) var startedWithInputMonitoring = false

    // Timestamp (CFAbsoluteTime) of the most recent real touch frame. Used
    // as a FUNCTIONAL signal that Input Monitoring is granted — Apple's
    // IOHIDCheckAccess lies (reports denied while data flows), so "are frames
    // actually arriving?" is the reliable question.
    private let frameLock = NSLock()
    private var lastFrameTime: Double = 0
    private var everReceivedFrame = false

    /// True once we've ever seen a touch frame — proof Input Monitoring works
    /// regardless of what IOHIDCheckAccess claims.
    var hasReceivedTouchData: Bool {
        frameLock.lock()
        defer { frameLock.unlock() }
        return everReceivedFrame
    }

    private func noteFrameReceived() {
        frameLock.lock()
        lastFrameTime = CFAbsoluteTimeGetCurrent()
        everReceivedFrame = true
        frameLock.unlock()
    }
    private var devices: [MultitouchBridge.MTDeviceRef] = []
    // Keeps the CFArray from MTDeviceCreateList alive; it owns the refs.
    private var deviceListOwner: CFArray?
    private var running = false
    private let queue = DispatchQueue(label: "com.kamenlevi.sleight.touches", qos: .userInteractive)
    private var rescanTimer: Timer?
    private var wakeObserver: NSObjectProtocol?

    // Maps a device's pointer bits (TouchFrame.deviceID) to its hardware
    // multitouch ID, for addressing haptic actuators. Read from the gesture
    // queue, written on start().
    private let idMapLock = NSLock()
    private var hardwareIDs: [UInt: UInt64] = [:]

    func hardwareID(for deviceID: UInt) -> UInt64? {
        idMapLock.lock()
        defer { idMapLock.unlock() }
        return hardwareIDs[deviceID]
    }

    // MultitouchSupport requires a plain C function pointer, so the frame
    // callback bounces through the shared instance.
    private static let contactCallback: MultitouchBridge.ContactCallback = { device, touchesPtr, count, timestamp, _ in
        guard let device else { return 0 }
        var touches: [Touch] = []
        if let touchesPtr, count > 0 {
            touches.reserveCapacity(Int(count))
            for i in 0..<Int(count) {
                let t = touchesPtr[i]
                // States 3 (touch start) and 4 (touching) are real contacts;
                // hover and lift-off phases are ignored.
                guard t.state == 3 || t.state == 4 else { continue }
                touches.append(Touch(
                    id: t.pathIndex,
                    x: t.normalized.position.x,
                    y: t.normalized.position.y,
                    size: t.total
                ))
            }
        }
        let frame = TouchFrame(
            deviceID: UInt(bitPattern: device),
            timestamp: timestamp,
            touches: touches
        )
        TouchStream.shared.dispatch(frame)
        return 0
    }

    private func dispatch(_ frame: TouchFrame) {
        noteFrameReceived()
        queue.async { [weak self] in
            self?.onFrame?(frame)
        }
    }

    func start() {
        guard MultitouchBridge.isAvailable else { return }
        stopDevices()
        if let list = MultitouchBridge.deviceList() {
            deviceListOwner = list.owner
            devices = list.devices
        }
        var ids: [UInt: UInt64] = [:]
        for device in devices {
            MultitouchBridge.register(device, callback: TouchStream.contactCallback)
            MultitouchBridge.start(device)
            if let hardwareID = MultitouchBridge.hardwareID(of: device) {
                ids[UInt(bitPattern: device)] = hardwareID
            }
        }
        idMapLock.lock()
        hardwareIDs = ids
        idMapLock.unlock()
        HapticEngine.shared.reset()
        deviceCount = devices.count
        startedWithInputMonitoring = Permissions.inputMonitoringReportedGranted
        running = true
        scheduleRescan()
    }

    func stop() {
        running = false
        rescanTimer?.invalidate()
        rescanTimer = nil
        stopDevices()
        deviceCount = 0
    }

    private func stopDevices() {
        for device in devices {
            if MultitouchBridge.isRunning(device) {
                MultitouchBridge.stop(device)
            }
            MultitouchBridge.unregister(device, callback: TouchStream.contactCallback)
        }
        devices = []
        deviceListOwner = nil
    }

    /// Bluetooth trackpads drop off on sleep/idle; poll the device list and
    /// rebuild when the set of devices changes so gestures keep working
    /// without a relaunch.
    private func scheduleRescan() {
        rescanTimer?.invalidate()
        let timer = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self, self.running else { return }
            guard let current = MultitouchBridge.deviceList() else { return }
            // Each MTDeviceCreateList call returns fresh instances, so
            // compare by count, not identity.
            if current.devices.count != self.devices.count {
                self.start()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        rescanTimer = timer

        if wakeObserver == nil {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self, self.running else { return }
                self.start()
            }
        }
    }
}
