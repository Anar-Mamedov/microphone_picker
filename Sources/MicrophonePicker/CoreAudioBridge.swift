import CoreAudio
import Foundation

/// Bir giriş (mikrofon) cihazının anlık görüntüsü.
///
/// `id` cihaz her yeniden bağlandığında değişebilir; kalıcı kimlik olarak
/// her zaman `uid` kullanılır.
struct AudioInputDevice: Equatable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let transportType: UInt32

    var symbolName: String {
        switch transportType {
        case kAudioDeviceTransportTypeBuiltIn:
            return "laptopcomputer"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return "headphones"
        case kAudioDeviceTransportTypeUSB:
            return "mic.fill"
        case kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeVirtual:
            return "waveform"
        case kAudioDeviceTransportTypeAirPlay:
            return "airplayaudio"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort:
            return "display"
        default:
            return "mic"
        }
    }
}

/// CoreAudio HAL üzerine ince bir Swift sarmalayıcı.
enum CoreAudioBridge {
    static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    static func makeAddress(
        _ selector: AudioObjectPropertySelector,
        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    // MARK: - Cihaz listesi

    static func inputDevices() -> [AudioInputDevice] {
        allDeviceIDs().compactMap { id in
            guard hasInputChannels(id) else { return nil }
            guard let uid = stringProperty(id, kAudioDevicePropertyDeviceUID), !isPrivate(uid: uid) else { return nil }
            let name = stringProperty(id, kAudioObjectPropertyName) ?? uid
            let transport = uint32Property(id, kAudioDevicePropertyTransportType) ?? 0
            return AudioInputDevice(id: id, uid: uid, name: name, transportType: transport)
        }
    }

    /// macOS, ses ayarlarında göstermediği dahili birleşik cihazlar oluşturur
    /// (ör. Ses Yalıtımı için `~:AMS2_Aggregate:0`). Bunların UID'si "~:" ile başlar.
    /// Kullanıcının Audio MIDI Setup'ta kendi oluşturduğu birleşik cihazlar
    /// UUID biçiminde bir UID aldığı için bu filtreden etkilenmez.
    private static func isPrivate(uid: String) -> Bool {
        uid.hasPrefix("~:")
    }

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var address = makeAddress(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size) == noErr else { return [] }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return [] }

        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    /// Cihazın giriş kapsamında en az bir kanalı var mı? (Yalnızca çıkış cihazlarını eler.)
    private static func hasInputChannels(_ deviceID: AudioDeviceID) -> Bool {
        var address = makeAddress(kAudioDevicePropertyStreamConfiguration, kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr, size > 0 else {
            return false
        }

        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { buffer.deallocate() }

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, buffer) == noErr else { return false }

        let list = UnsafeMutableAudioBufferListPointer(buffer.assumingMemoryBound(to: AudioBufferList.self))
        return list.contains { $0.mNumberChannels > 0 }
    }

    // MARK: - Varsayılan giriş cihazı

    static func defaultInputDeviceID() -> AudioDeviceID? {
        var address = makeAddress(kAudioHardwarePropertyDefaultInputDevice)
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &deviceID) == noErr,
              deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    @discardableResult
    static func setDefaultInputDevice(_ deviceID: AudioDeviceID) -> OSStatus {
        var address = makeAddress(kAudioHardwarePropertyDefaultInputDevice)
        var value = deviceID
        return AudioObjectSetPropertyData(
            systemObject,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &value
        )
    }

    // MARK: - Dinleyiciler

    /// Sistem nesnesi üzerinde bir özelliği dinler. Geri çağırma ana kuyrukta çalışır.
    static func addSystemListener(
        _ selector: AudioObjectPropertySelector,
        handler: @escaping () -> Void
    ) -> AudioObjectPropertyListenerBlock? {
        var address = makeAddress(selector)
        let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }
        let status = AudioObjectAddPropertyListenerBlock(systemObject, &address, DispatchQueue.main, block)
        return status == noErr ? block : nil
    }

    // MARK: - Özellik yardımcıları

    private static func stringProperty(
        _ objectID: AudioObjectID,
        _ selector: AudioObjectPropertySelector
    ) -> String? {
        var address = makeAddress(selector)
        guard AudioObjectHasProperty(objectID, &address) else { return nil }

        var value: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, $0)
        }
        guard status == noErr, let value else { return nil }
        return value as String
    }

    private static func uint32Property(
        _ objectID: AudioObjectID,
        _ selector: AudioObjectPropertySelector
    ) -> UInt32? {
        var address = makeAddress(selector)
        guard AudioObjectHasProperty(objectID, &address) else { return nil }

        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }
}
