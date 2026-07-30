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
        inputChannelCount(deviceID) > 0
    }

    static func inputChannelCount(_ deviceID: AudioDeviceID) -> Int {
        var address = makeAddress(kAudioDevicePropertyStreamConfiguration, kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr, size > 0 else {
            return 0
        }

        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { buffer.deallocate() }

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, buffer) == noErr else { return 0 }

        let list = UnsafeMutableAudioBufferListPointer(buffer.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
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

    // MARK: - Giriş kontrolleri (seviye ve susturma)

    static func inputAddress(
        _ selector: AudioObjectPropertySelector,
        _ element: AudioObjectPropertyElement
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: element
        )
    }

    /// Bir kontrolün yazılabildiği elemanlar.
    ///
    /// Cihazların çoğunda tek bir "master" elemanı (0) vardır — RØDE PodMic USB,
    /// dahili mikrofon ve diğer USB cihaz seviye için bu gruptadır. Bazı ses
    /// arabirimleri master sunmaz, yalnızca kanal başına kontrol verir; o durumda
    /// tüm kanallara yazarız. Kontrolü hiç sunmayan cihazlarda liste boş döner —
    /// ör. RØDE PodMic USB'de susturma kontrolü yoktur.
    private static func settableElements(
        _ deviceID: AudioDeviceID,
        _ selector: AudioObjectPropertySelector
    ) -> [AudioObjectPropertyElement] {
        let main = AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        if isSettable(deviceID, selector, main) { return [main] }

        let channels = max(inputChannelCount(deviceID), 1)
        return (1...channels)
            .map(AudioObjectPropertyElement.init)
            .filter { isSettable(deviceID, selector, $0) }
    }

    private static func isSettable(
        _ deviceID: AudioDeviceID,
        _ selector: AudioObjectPropertySelector,
        _ element: AudioObjectPropertyElement
    ) -> Bool {
        var address = inputAddress(selector, element)
        guard AudioObjectHasProperty(deviceID, &address) else { return false }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(deviceID, &address, &settable) == noErr else { return false }
        return settable.boolValue
    }

    // MARK: Seviye

    static func hasVolumeControl(_ deviceID: AudioDeviceID) -> Bool {
        !settableElements(deviceID, kAudioDevicePropertyVolumeScalar).isEmpty
    }

    /// 0.0–1.0 aralığında, macOS'un giriş seviyesi kaydırıcısıyla aynı ölçek.
    static func inputVolume(_ deviceID: AudioDeviceID) -> Float? {
        guard let element = settableElements(deviceID, kAudioDevicePropertyVolumeScalar).first else {
            return nil
        }
        var address = inputAddress(kAudioDevicePropertyVolumeScalar, element)
        var value: Float = 0
        var size = UInt32(MemoryLayout<Float>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    @discardableResult
    static func setInputVolume(_ deviceID: AudioDeviceID, _ value: Float) -> Bool {
        let elements = settableElements(deviceID, kAudioDevicePropertyVolumeScalar)
        guard !elements.isEmpty else { return false }

        let clamped = min(max(value, 0), 1)
        var wroteAny = false
        for element in elements {
            var address = inputAddress(kAudioDevicePropertyVolumeScalar, element)
            var scalar = clamped
            let status = AudioObjectSetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                UInt32(MemoryLayout<Float>.size),
                &scalar
            )
            if status == noErr { wroteAny = true }
        }
        return wroteAny
    }

    // MARK: Susturma

    static func hasMuteControl(_ deviceID: AudioDeviceID) -> Bool {
        !settableElements(deviceID, kAudioDevicePropertyMute).isEmpty
    }

    /// Kontrolü olmayan cihazlarda `nil` döner — "susturulmamış" ile karıştırılmamalı.
    static func isInputMuted(_ deviceID: AudioDeviceID) -> Bool? {
        guard let element = settableElements(deviceID, kAudioDevicePropertyMute).first else { return nil }
        var address = inputAddress(kAudioDevicePropertyMute, element)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }

    @discardableResult
    static func setInputMuted(_ deviceID: AudioDeviceID, _ muted: Bool) -> Bool {
        let elements = settableElements(deviceID, kAudioDevicePropertyMute)
        guard !elements.isEmpty else { return false }

        var wroteAny = false
        for element in elements {
            var address = inputAddress(kAudioDevicePropertyMute, element)
            var value: UInt32 = muted ? 1 : 0
            let status = AudioObjectSetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                UInt32(MemoryLayout<UInt32>.size),
                &value
            )
            if status == noErr { wroteAny = true }
        }
        return wroteAny
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

    /// Belirli bir cihazın giriş kontrolünü (seviye ya da susturma) dinler.
    /// Sistem dinleyicilerinin aksine bu, cihaz nesnesine bağlanır; cihaz yeniden
    /// bağlandığında `AudioDeviceID` değiştiği için sökülüp yeniden takılması gerekir.
    /// Eleman joker karakteri kullanılır, böylece kanal başına kontrol veren
    /// cihazlarda da her kanalın değişimi yakalanır.
    static func addInputListener(
        _ deviceID: AudioDeviceID,
        _ selector: AudioObjectPropertySelector,
        handler: @escaping () -> Void
    ) -> AudioObjectPropertyListenerBlock? {
        var address = inputAddress(selector, kAudioObjectPropertyElementWildcard)
        let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }
        let status = AudioObjectAddPropertyListenerBlock(deviceID, &address, DispatchQueue.main, block)
        return status == noErr ? block : nil
    }

    static func removeInputListener(
        _ deviceID: AudioDeviceID,
        _ selector: AudioObjectPropertySelector,
        _ block: @escaping AudioObjectPropertyListenerBlock
    ) {
        var address = inputAddress(selector, kAudioObjectPropertyElementWildcard)
        AudioObjectRemovePropertyListenerBlock(deviceID, &address, DispatchQueue.main, block)
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
