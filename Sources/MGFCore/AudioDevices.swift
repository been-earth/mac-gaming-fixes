import CoreAudio
import Foundation

public struct AudioDevice: Identifiable, Equatable {
    public enum Transport: String { case builtIn = "built-in", usb, bluetooth, virtual, other }

    public let id: AudioDeviceID
    public let name: String
    public let hasInput: Bool
    public let hasOutput: Bool
    public let transport: Transport
    public let sampleRate: Double
}

/// The system's audio devices, its default input and output, and the input level.
public enum AudioSystem {
    private static let system = AudioObjectID(kAudioObjectSystemObject)

    private static func address(_ selector: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                                _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    private static func read<T: BitwiseCopyable>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ initial: T) -> T? {
        var address = address, value = initial, size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func size(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Int {
        var address = address, size = UInt32(0)
        return AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr ? Int(size) : 0
    }

    private static func check(_ status: OSStatus, _ what: String) throws {
        guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "\(what): OSStatus \(status)"]) }
    }

    public static func devices() -> [AudioDevice] {
        let list = address(kAudioHardwarePropertyDevices)
        var ids = [AudioDeviceID](repeating: 0, count: size(system, list) / MemoryLayout<AudioDeviceID>.size)
        var listAddress = list, bytes = UInt32(ids.count * MemoryLayout<AudioDeviceID>.size)
        guard !ids.isEmpty, AudioObjectGetPropertyData(system, &listAddress, 0, nil, &bytes, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            let hasInput = size(id, address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput)) > 0
            let hasOutput = size(id, address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeOutput)) > 0
            guard hasInput || hasOutput, let name = name(of: id) else { return nil }
            let transport: AudioDevice.Transport
            switch read(id, address(kAudioDevicePropertyTransportType), UInt32(0)) ?? 0 {
            case kAudioDeviceTransportTypeBuiltIn: transport = .builtIn
            case kAudioDeviceTransportTypeUSB: transport = .usb
            case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: transport = .bluetooth
            case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate: transport = .virtual
            default: transport = .other
            }
            return AudioDevice(id: id, name: name, hasInput: hasInput, hasOutput: hasOutput, transport: transport,
                               sampleRate: read(id, address(kAudioDevicePropertyNominalSampleRate), Float64(0)) ?? 0)
        }
    }

    private static func name(of device: AudioDeviceID) -> String? {
        var address = address(kAudioObjectPropertyName), value: Unmanaged<CFString>?, size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private static func defaultSelector(input: Bool) -> AudioObjectPropertySelector {
        input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice
    }

    public static func defaultDevice(input: Bool) -> AudioDeviceID? {
        read(system, address(defaultSelector(input: input)), AudioDeviceID(0)).flatMap { $0 == 0 ? nil : $0 }
    }

    public static func setDefault(_ device: AudioDeviceID, input: Bool) throws {
        var address = address(defaultSelector(input: input)), device = device
        try check(AudioObjectSetPropertyData(system, &address, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &device), "set default device")
    }

    /// Elements that carry a settable input volume: the main one, or the left and right channels.
    private static func volumeElements(_ device: AudioDeviceID) -> [AudioObjectPropertyElement] {
        [[kAudioObjectPropertyElementMain], [1, 2]].first { elements in
            elements.allSatisfy { element in
                var address = address(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeInput, element), settable = DarwinBoolean(false)
                return AudioObjectHasProperty(device, &address) && AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
            }
        } ?? []
    }

    /// 0...1, nil when the device has no software input volume.
    public static func inputVolume(_ device: AudioDeviceID) -> Float? {
        let levels = volumeElements(device).compactMap { read(device, address(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeInput, $0), Float32(0)) }
        return levels.isEmpty ? nil : levels.reduce(0, +) / Float(levels.count)
    }

    public static func setInputVolume(_ device: AudioDeviceID, _ volume: Float) throws {
        for element in volumeElements(device) {
            var address = address(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeInput, element), level = Float32(min(max(volume, 0), 1))
            try check(AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &level), "set input volume")
        }
    }

    /// Calls `handler` on the main queue when devices come and go or a default device changes.
    public static func observe(_ handler: @escaping () -> Void) {
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDefaultOutputDevice] {
            var address = address(selector)
            AudioObjectAddPropertyListenerBlock(system, &address, .main) { _, _ in handler() }
        }
    }
}
