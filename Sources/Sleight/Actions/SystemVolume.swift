import CoreAudio
import Foundation

/// Direct CoreAudio control of the default output device, giving the dial
/// smooth sub-percent steps instead of the 16 coarse notches of volume keys.
enum SystemVolume {
    private static func defaultOutputDevice() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    // 'vmvc' — virtual main volume; the SDK constant name varies by version.
    private static let virtualMainVolume = AudioObjectPropertySelector(0x766D_7663)

    private static func volumeAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: virtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    static func get() -> Float? {
        guard let device = defaultOutputDevice() else { return nil }
        var address = volumeAddress()
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr else {
            return nil
        }
        return volume
    }

    static func set(_ value: Float) {
        guard let device = defaultOutputDevice() else { return }
        var address = volumeAddress()
        var volume = Float32(min(max(value, 0), 1))
        var settable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr,
              settable.boolValue else { return }
        AudioObjectSetPropertyData(
            device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &volume
        )
        if volume > 0, isMuted() == true {
            setMuted(false)
        }
    }

    static func isMuted() -> Bool? {
        guard let device = defaultOutputDevice() else { return nil }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted) == noErr else {
            return nil
        }
        return muted != 0
    }

    static func setMuted(_ muted: Bool) {
        guard let device = defaultOutputDevice() else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &address) else { return }
        var value: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(
            device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value
        )
    }
}
