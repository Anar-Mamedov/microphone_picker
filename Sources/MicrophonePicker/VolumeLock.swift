import CoreAudio
import Foundation

/// Kilitli mikrofonun giriş seviyesini ve susturma durumunu, kullanıcının o cihaz
/// için belirlediği hâlde tutar.
///
/// Kapsam bilinçli olarak dar: ayarlar **cihaz başına** saklanır, ama yalnızca
/// o an kilitli olan mikrofona uygulanır. Diğer cihazların kayıtlı değerleri
/// hatırlanır; sistem onları kıssa ya da sustursa bile bu sınıf karışmaz.
final class VolumeLock {
    private enum Keys {
        static let targets = "inputVolumeTargets"
        static let preventMute = "preventMuteUIDs"
    }

    /// Bir düzeltmenin türü — menü mesajını ve çekişme uyarısını belirler.
    private enum Correction {
        case volume(from: Float, to: Float)
        case unmute
    }

    /// Donanım, yazdığımız değeri en yakın adıma yuvarlar (RØDE'de 22–63 dB aralığı
    /// ayrık adımlarla ilerler). Bu yüzden tam eşitlik değil, tolerans karşılaştırması
    /// yapıyoruz — aksi hâlde her turda "eşit değil" deyip sonsuza kadar yazardık.
    private static let tolerance: Float = 0.01
    private static let watchdogInterval: TimeInterval = 1.0

    /// Savaş algılayıcı: bir uygulamanın otomatik seviye ayarı (AGC) ile karşılıklı
    /// itişmeye girersek ses "pompalar" ve donanım gain'ine saniyede onlarca kez
    /// yazarız. Bunu tespit edip geri çekiliyor ve kullanıcıya sebebini söylüyoruz.
    private static let fightWindow: TimeInterval = 3.0
    private static let fightThreshold = 5
    private static let cooldown: TimeInterval = 30.0

    var onStateChange: (() -> Void)?

    /// Kilit uygulanan cihaz — mikrofon kilidiyle senkron tutulur.
    private(set) var device: AudioInputDevice?

    /// Son düzeltme: ne zaman, hangi seviyeden hangisine, o sırada mikrofonu kim kullanıyordu.
    private(set) var lastEvent: String?
    private(set) var warning: String?
    private(set) var warningSuspects: String?
    private(set) var warningDetail: String?

    private var volumeListener: AudioObjectPropertyListenerBlock?
    private var muteListener: AudioObjectPropertyListenerBlock?
    private var listenerDeviceID: AudioDeviceID?
    private var watchdog: Timer?

    /// Cihazın hedefe en yakın oturduğu gerçek değer; kuantalama farkını yutar.
    private var settled: Float?
    private var corrections: [Date] = []
    private var pausedUntil: Date?
    /// Çekişme penceresi boyunca mikrofonu kullanırken yakalanan uygulamalar.
    private var suspects: Set<String> = []

    private let defaults = UserDefaults.standard

    // MARK: - Hedefler

    private var targets: [String: Float] {
        get {
            let raw = defaults.dictionary(forKey: Keys.targets) as? [String: Double] ?? [:]
            return raw.mapValues { Float($0) }
        }
        set {
            defaults.set(newValue.mapValues { Double($0) }, forKey: Keys.targets)
        }
    }

    func target(for uid: String) -> Float? {
        targets[uid]
    }

    // MARK: - Susturma engeli

    private var preventMuteUIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Keys.preventMute) ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: Keys.preventMute) }
    }

    func preventsMute(for uid: String) -> Bool {
        preventMuteUIDs.contains(uid)
    }

    func setPreventsMute(_ enabled: Bool, for device: AudioInputDevice) {
        var updated = preventMuteUIDs
        if enabled {
            updated.insert(device.uid)
        } else {
            updated.remove(device.uid)
        }
        preventMuteUIDs = updated

        resetDiagnostics()
        if enabled {
            // Şu an susturulmuşsa hemen aç — kullanıcı bunu bekler.
            CoreAudioBridge.setInputMuted(device.id, false)
        }
        onStateChange?()
    }

    /// Kullanıcı kaydırıcıyı oynattı: değeri o cihaz için kaydet ve hemen uygula.
    func setTarget(_ value: Float, for device: AudioInputDevice) {
        var updated = targets
        updated[device.uid] = min(max(value, 0), 1)
        targets = updated

        resetDiagnostics()
        settled = nil

        CoreAudioBridge.setInputVolume(device.id, value)
        settled = CoreAudioBridge.inputVolume(device.id)
        onStateChange?()
    }

    func clearTarget(for device: AudioInputDevice) {
        var updated = targets
        updated.removeValue(forKey: device.uid)
        targets = updated

        resetDiagnostics()
        settled = nil
        lastEvent = nil
        onStateChange?()
    }

    private func resetDiagnostics() {
        corrections.removeAll()
        suspects.removeAll()
        pausedUntil = nil
        warning = nil
        warningSuspects = nil
        warningDetail = nil
    }

    // MARK: - Yaşam döngüsü

    func start() {
        // Bkz. MicrophoneLock: `.common` mod, menü açıkken de nöbet sürsün.
        let timer = Timer(timeInterval: Self.watchdogInterval, repeats: true) { [weak self] _ in
            self?.enforce()
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    /// Mikrofon kilidi hangi cihazdaysa seviye kilidi de onu izler.
    /// Cihaz yeniden bağlandığında kimlik değiştiği için dinleyici yenilenir.
    func follow(_ newDevice: AudioInputDevice?) {
        guard newDevice?.id != listenerDeviceID else { return }

        if let listenerDeviceID {
            if let volumeListener {
                CoreAudioBridge.removeInputListener(listenerDeviceID, kAudioDevicePropertyVolumeScalar, volumeListener)
            }
            if let muteListener {
                CoreAudioBridge.removeInputListener(listenerDeviceID, kAudioDevicePropertyMute, muteListener)
            }
        }
        volumeListener = nil
        muteListener = nil
        listenerDeviceID = nil

        device = newDevice
        settled = nil
        lastEvent = nil
        resetDiagnostics()

        guard let newDevice else {
            onStateChange?()
            return
        }

        volumeListener = CoreAudioBridge.addInputListener(newDevice.id, kAudioDevicePropertyVolumeScalar) { [weak self] in
            self?.enforce()
        }
        muteListener = CoreAudioBridge.addInputListener(newDevice.id, kAudioDevicePropertyMute) { [weak self] in
            self?.enforce()
        }
        listenerDeviceID = newDevice.id

        enforce()
        onStateChange?()
    }

    // MARK: - Uygulama

    private func enforce() {
        guard let device else { return }

        if let pausedUntil {
            guard Date() >= pausedUntil else { return }
            self.pausedUntil = nil
        }

        enforceVolume(on: device)
        enforceMute(on: device)
    }

    private func enforceVolume(on device: AudioInputDevice) {
        guard let target = targets[device.uid] else { return }
        guard let current = CoreAudioBridge.inputVolume(device.id) else { return }

        // Hedefimiz, cihazın hedefe en yakın oturduğu gerçek değer.
        let goal = settled ?? target
        guard abs(current - goal) > Self.tolerance else { return }

        guard CoreAudioBridge.setInputVolume(device.id, target) else { return }
        settled = CoreAudioBridge.inputVolume(device.id) ?? target

        recordCorrection(.volume(from: current, to: target))
        onStateChange?()
    }

    private func enforceMute(on device: AudioInputDevice) {
        guard preventMuteUIDs.contains(device.uid) else { return }
        // `nil` = cihazın susturma kontrolü yok; "susturulmamış" ile karıştırma.
        guard CoreAudioBridge.isInputMuted(device.id) == true else { return }
        guard CoreAudioBridge.setInputMuted(device.id, false) else { return }

        recordCorrection(.unmute)
        onStateChange?()
    }

    private func recordCorrection(_ correction: Correction) {
        let now = Date()
        // Suçluyu tam düzeltme anında örnekle — kontrolü oynatan uygulama
        // neredeyse her zaman o sırada kayıt da yapıyor olur.
        let capturing = AudioProcesses.capturingInput()

        let summary: String
        switch correction {
        case .volume(let from, let to):
            summary = "\(Self.percent(from)) → \(Self.percent(to))"
        case .unmute:
            summary = "susturma kaldırıldı"
        }
        lastEvent = "\(Self.timestamp(now)) · \(summary)"
            + (capturing.isEmpty ? "" : " · \(capturing.joined(separator: ", "))")

        corrections.append(now)
        corrections.removeAll { now.timeIntervalSince($0) > Self.fightWindow }
        suspects.formUnion(capturing)

        guard corrections.count >= Self.fightThreshold else { return }

        let count = corrections.count
        let caught = suspects.sorted()
        corrections.removeAll()
        suspects.removeAll()
        pausedUntil = now.addingTimeInterval(Self.cooldown)

        // Sayıya göre değişen Türkçe ekten kaçınmak için "son müdahale %50" biçimi
        // kullanılıyor — "%50'ye" / "%90'a" / "%100'e" hepsi farklı ek alıyor.
        let subject: String
        let setting: String
        switch correction {
        case .volume(let from, _):
            subject = "Seviye çekişmesi: \(Int(Self.fightWindow)) sn içinde \(count) düzeltme "
                + "(son müdahale \(Self.percent(from)))"
            setting = "otomatik mikrofon seviyesi"
        case .unmute:
            subject = "Susturma çekişmesi: \(Int(Self.fightWindow)) sn içinde \(count) kez susturuldu"
            setting = "susturma"
        }
        warning = "\(subject) — kilit \(Int(Self.cooldown)) sn duraklatıldı"

        if caught.isEmpty {
            warningSuspects = "O sırada mikrofonu kullanan uygulama yoktu — "
                + "bir sürücü ya da sistem ayarı olabilir"
            warningDetail = nil
        } else {
            warningSuspects = "O sırada mikrofonu kullanan: \(caught.joined(separator: ", "))"
            warningDetail = caught.count == 1
                ? "Kalıcı çözüm: \(caught[0]) içindeki \(setting) ayarını kapatın."
                : "Kalıcı çözüm: bu uygulamaların \(setting) ayarını kapatın."
        }
    }

    private static func percent(_ value: Float) -> String {
        "%\(Int((value * 100).rounded()))"
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
