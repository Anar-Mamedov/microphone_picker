import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let lock = MicrophoneLock()
    private var loginItemError: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.toolTip = "Mikrofon Kilidi"

        menu.delegate = self
        // Etkinlik durumunu kendimiz yönetiyoruz (ör. kilit yokken "Kilidi Kaldır" pasif).
        menu.autoenablesItems = false
        statusItem.menu = menu

        lock.onStateChange = { [weak self] in self?.updateStatusIcon() }
        lock.start()

        updateStatusIcon()
    }

    // MARK: - Menü çubuğu ikonu

    private func updateStatusIcon() {
        let symbol: String
        let description: String

        switch lock.state {
        case .off:
            symbol = "mic"
            description = "Kilit kapalı"
        case .enforced(let device):
            symbol = "mic.fill"
            description = "Kilitli: \(device.name)"
        case .waiting:
            symbol = "mic.slash.fill"
            description = "Kilitli cihaz bağlı değil"
        }

        statusItem.button?.image = image(named: symbol, fallback: "mic")
        statusItem.button?.toolTip = description
    }

    private func image(named name: String, fallback: String? = nil) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            ?? fallback.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        image?.isTemplate = true
        return image
    }

    // MARK: - Menü

    func menuNeedsUpdate(_ menu: NSMenu) {
        lock.refreshDevices()
        rebuild(menu)
    }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(headerItem())
        if let warning = mismatchWarningItem() {
            menu.addItem(warning)
        }

        menu.addItem(.separator())
        menu.addItem(sectionItem("Giriş Cihazları"))

        if lock.devices.isEmpty {
            menu.addItem(disabledItem("Giriş cihazı bulunamadı"))
        } else {
            for device in lock.devices {
                menu.addItem(deviceItem(device))
            }
        }

        menu.addItem(.separator())

        let unlock = NSMenuItem(
            title: "Kilidi Kaldır (otomatiğe dön)",
            action: #selector(unlockTapped),
            keyEquivalent: ""
        )
        unlock.target = self
        unlock.isEnabled = lock.lockedUID != nil
        menu.addItem(unlock)

        menu.addItem(.separator())

        let loginToggle = NSMenuItem(
            title: "Oturum Açılışında Başlat",
            action: #selector(loginItemTapped),
            keyEquivalent: ""
        )
        loginToggle.target = self
        loginToggle.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(loginToggle)

        if let loginItemError {
            menu.addItem(disabledItem("Girişte başlatma hatası: \(loginItemError)"))
        }

        if let lastEvent = lock.lastEvent {
            menu.addItem(disabledItem("Son işlem: \(lastEvent)"))
        }

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Çık", action: #selector(quitTapped), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func headerItem() -> NSMenuItem {
        let title: String
        switch lock.state {
        case .off:
            title = "Kilit kapalı"
        case .enforced(let device):
            title = "Kilitli: \(device.name)"
        case .waiting:
            title = "Kilitli: \(lock.lockedDeviceDisplayName ?? "?") (bağlı değil)"
        }

        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)]
        )
        item.isEnabled = false
        return item
    }

    /// Kilit açıkken sistem başka bir cihazda takılı kaldıysa (ör. cihaz meşgul)
    /// kullanıcıya sebebini gösterir.
    private func mismatchWarningItem() -> NSMenuItem? {
        guard case .enforced(let target) = lock.state,
              let current = lock.currentSystemInput,
              current.id != target.id else { return nil }
        return disabledItem("⚠︎ Sistem şu an: \(current.name)")
    }

    private func deviceItem(_ device: AudioInputDevice) -> NSMenuItem {
        let item = NSMenuItem(title: device.name, action: #selector(deviceTapped(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = device.uid
        item.state = (device.uid == lock.lockedUID) ? .on : .off
        item.image = image(named: device.symbolName, fallback: "mic")
        return item
    }

    private func sectionItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        item.isEnabled = false
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        item.isEnabled = false
        return item
    }

    // MARK: - Eylemler

    @objc private func deviceTapped(_ sender: NSMenuItem) {
        guard let uid = sender.representedObject as? String,
              let device = lock.devices.first(where: { $0.uid == uid }) else { return }
        lock.lock(to: device)
    }

    @objc private func unlockTapped() {
        lock.unlock()
    }

    @objc private func loginItemTapped() {
        loginItemError = LoginItem.toggle()
    }

    @objc private func quitTapped() {
        NSApp.terminate(nil)
    }
}
