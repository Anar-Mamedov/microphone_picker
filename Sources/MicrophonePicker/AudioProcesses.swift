import AppKit
import CoreAudio

/// "Mikrofonu şu an kim kullanıyor?" sorusunu cevaplar.
///
/// CoreAudio, bir özelliği hangi işlemin değiştirdiğini **söylemez** — böyle bir API
/// yok. Yapabileceğimiz en iyi şey, seviyeyi düzelttiğimiz anda mikrofondan kayıt
/// yapan uygulamaları örneklemek. Seviyeyi oynatan uygulama neredeyse her zaman
/// aynı anda kayıt da yapıyor olur, o yüzden pratikte doğru adı verir. Yine de
/// bir tahmindir; menüde "sürekli değiştiren" değil "mikrofonu kullanan" diye sunulur.
///
/// macOS 14.4'te gelen Audio Process nesnelerini kullanır; daha eski sürümlerde
/// boş liste döner ve menü yalnızca seviye bilgisini gösterir.
enum AudioProcesses {
    struct Entry {
        let name: String
        let isCapturingInput: Bool
    }

    /// Şu anda mikrofondan kayıt yapan uygulamaların adları, tekrarsız.
    static func capturingInput() -> [String] {
        var names: [String] = []
        for entry in all() where entry.isCapturingInput {
            if !names.contains(entry.name) { names.append(entry.name) }
        }
        return names
    }

    /// Ses alt sistemine kayıtlı tüm işlemler, çözümlenmiş adlarıyla.
    static func all() -> [Entry] {
        guard #available(macOS 14.4, *) else { return [] }

        return processObjectIDs().compactMap { object in
            let pid = uint32(object, kAudioProcessPropertyPID).map { pid_t(Int32(bitPattern: $0)) }
            let bundleID = string(object, kAudioProcessPropertyBundleID)
            guard let name = displayName(pid: pid, bundleID: bundleID) else { return nil }
            return Entry(
                name: name,
                isCapturingInput: uint32(object, kAudioProcessPropertyIsRunningInput) == 1
            )
        }
    }

    @available(macOS 14.4, *)
    private static func processObjectIDs() -> [AudioObjectID] {
        var address = CoreAudioBridge.makeAddress(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(CoreAudioBridge.systemObject, &address, 0, nil, &size) == noErr,
              size > 0 else { return [] }

        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            CoreAudioBridge.systemObject, &address, 0, nil, &size, &ids
        ) == noErr else { return [] }
        return ids
    }

    /// Yardımcı işlemleri ana uygulamaya indirger: mikrofonu Chrome'un kendisi değil
    /// `com.google.Chrome.helper` açar, ama kullanıcı "Google Chrome" görmeli.
    private static func displayName(pid: pid_t?, bundleID: String?) -> String? {
        if let bundleID, !bundleID.isEmpty {
            let parent = bundleID.replacingOccurrences(of: ".helper", with: "")
                .replacingOccurrences(of: ".Helper", with: "")
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: parent).first,
               let name = app.localizedName {
                return strippingHelperSuffix(name)
            }
        }

        if let pid, let name = NSRunningApplication(processIdentifier: pid)?.localizedName {
            return strippingHelperSuffix(name)
        }

        return bundleID.flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func strippingHelperSuffix(_ name: String) -> String {
        let suffixes = [
            " Helper (Renderer)", " Helper (GPU)", " Helper (Plugin)",
            " Graphics and Media", " Helper"
        ]
        for suffix in suffixes where name.hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        return name
    }

    // MARK: - Özellik yardımcıları

    private static func uint32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = CoreAudioBridge.makeAddress(selector)
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = CoreAudioBridge.makeAddress(selector)
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var value: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
        }
        guard status == noErr, let value else { return nil }
        return value as String
    }
}
