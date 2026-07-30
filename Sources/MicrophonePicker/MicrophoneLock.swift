import CoreAudio
import Foundation

/// Kilidin anlık durumu — menü çubuğu ikonunu ve başlığı belirler.
enum LockState: Equatable {
    /// Kilit kapalı, sistem ne isterse o.
    case off
    /// Kilitli cihaz bağlı ve sistem girişi olarak ayarlı.
    case enforced(AudioInputDevice)
    /// Kilitli cihaz şu anda bağlı değil; geri döndüğünde otomatik uygulanacak.
    case waiting(uid: String)
}

/// Seçilen mikrofonu sistemin varsayılan giriş cihazı olarak tutan çekirdek mantık.
///
/// Üç savunma hattı var:
///   1. `kAudioHardwarePropertyDefaultInputDevice` dinleyicisi — sistem cihazı
///      değiştirir değiştirmez haber alırız.
///   2. `kAudioHardwarePropertyDevices` dinleyicisi — kulaklık takılıp çıkarıldığında
///      tetiklenir, ardından kısa bir "tekrar dene" serisi çalışır (macOS bazen
///      cihaz listesini güncelledikten birkaç yüz ms sonra varsayılanı değiştirir).
///   3. 1 saniyelik nöbetçi zamanlayıcı — hiçbir bildirim üretmeden varsayılanı
///      değiştiren uygulamaları (Zoom, Teams vb.) yakalar.
final class MicrophoneLock {
    private enum Keys {
        static let lockedUID = "lockedInputDeviceUID"
    }

    /// Bir cihaz olayından sonra yeniden deneme anları (saniye).
    private static let retryDelays: [TimeInterval] = [0.2, 0.6, 1.2, 2.0, 3.5, 5.0]
    private static let watchdogInterval: TimeInterval = 1.0

    /// Durum değiştiğinde UI'ı tazelemek için çağrılır (ana iş parçacığı).
    var onStateChange: (() -> Void)?

    private(set) var devices: [AudioInputDevice] = []
    private(set) var lastEvent: String?

    private var listeners: [AudioObjectPropertyListenerBlock] = []
    private var watchdog: Timer?

    private let defaults = UserDefaults.standard

    var lockedUID: String? {
        get { defaults.string(forKey: Keys.lockedUID) }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Keys.lockedUID)
            } else {
                defaults.removeObject(forKey: Keys.lockedUID)
            }
        }
    }

    var lockedDevice: AudioInputDevice? {
        guard let uid = lockedUID else { return nil }
        return devices.first { $0.uid == uid }
    }

    /// Kilitli cihaz bağlı değilken bile kullanıcıya bir isim gösterebilmek için
    /// son bilinen adı saklıyoruz.
    var lockedDeviceDisplayName: String? {
        guard let uid = lockedUID else { return nil }
        if let device = devices.first(where: { $0.uid == uid }) { return device.name }
        return defaults.string(forKey: "lastKnownName.\(uid)") ?? uid
    }

    var state: LockState {
        guard let uid = lockedUID else { return .off }
        guard let device = devices.first(where: { $0.uid == uid }) else { return .waiting(uid: uid) }
        return .enforced(device)
    }

    var currentSystemInput: AudioInputDevice? {
        guard let id = CoreAudioBridge.defaultInputDeviceID() else { return nil }
        return devices.first { $0.id == id }
    }

    // MARK: - Yaşam döngüsü

    func start() {
        refreshDevices()

        if let block = CoreAudioBridge.addSystemListener(kAudioHardwarePropertyDefaultInputDevice, handler: { [weak self] in
            self?.handleDefaultInputChanged()
        }) {
            listeners.append(block)
        }

        if let block = CoreAudioBridge.addSystemListener(kAudioHardwarePropertyDevices, handler: { [weak self] in
            self?.handleDeviceListChanged()
        }) {
            listeners.append(block)
        }

        watchdog = Timer.scheduledTimer(withTimeInterval: Self.watchdogInterval, repeats: true) { [weak self] _ in
            self?.enforce()
        }
        watchdog?.tolerance = 0.25

        enforce()
    }

    // MARK: - Kullanıcı eylemleri

    func lock(to device: AudioInputDevice) {
        lockedUID = device.uid
        defaults.set(device.name, forKey: "lastKnownName.\(device.uid)")
        enforce()
        notifyStateChange()
    }

    func unlock() {
        lockedUID = nil
        lastEvent = "Kilit kaldırıldı"
        notifyStateChange()
    }

    func refreshDevices() {
        let fresh = CoreAudioBridge.inputDevices()
        guard fresh != devices else { return }
        devices = fresh
        for device in fresh {
            defaults.set(device.name, forKey: "lastKnownName.\(device.uid)")
        }
    }

    // MARK: - Olaylar

    private func handleDefaultInputChanged() {
        refreshDevices()
        enforce()
        notifyStateChange()
    }

    private func handleDeviceListChanged() {
        refreshDevices()
        enforce()
        scheduleRetryBurst()
        notifyStateChange()
    }

    /// macOS, cihaz listesini güncelledikten *sonra* varsayılanı değiştirebiliyor;
    /// bu yüzden olayın ardından birkaç kez daha bastırıyoruz.
    private func scheduleRetryBurst() {
        for delay in Self.retryDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                self.refreshDevices()
                self.enforce()
            }
        }
    }

    // MARK: - Uygulama

    /// Kilitli cihaz varsa ve sistem girişi ondan farklıysa geri alır.
    private func enforce() {
        guard let uid = lockedUID else { return }

        guard let target = devices.first(where: { $0.uid == uid }) else {
            // Cihaz bağlı değil — sistemle kavga etmenin anlamı yok, dönmesini bekliyoruz.
            return
        }

        let currentID = CoreAudioBridge.defaultInputDeviceID()
        guard currentID != target.id else { return }

        let previousName = currentID.flatMap { id in devices.first { $0.id == id }?.name } ?? "bilinmeyen"
        let status = CoreAudioBridge.setDefaultInputDevice(target.id)

        if status == noErr {
            lastEvent = "\(Self.timestamp()) — \(previousName) → \(target.name)"
        } else {
            lastEvent = "\(Self.timestamp()) — geri alınamadı (OSStatus \(status))"
        }

        notifyStateChange()
    }

    private func notifyStateChange() {
        onStateChange?()
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }
}
