import AppKit

/// Menü öğesi olarak gömülen giriş seviyesi kaydırıcısı.
///
/// Kaydırıcı sürekli çalışır (etiket anında güncellenir) ama cihaza yazma işlemi
/// kısılır: RØDE'de bu kaydırıcı donanım preamp gain'ini sürüyor, yani her yazma
/// USB üzerinden mikrofona giden bir komut. Sürükleme boyunca saniyede 60 komut
/// göndermenin anlamı yok — 80 ms'de bir yazıyor, düğme bırakıldığında son değeri
/// mutlaka gönderiyoruz.
final class VolumeSliderView: NSView {
    private static let writeInterval: TimeInterval = 0.08

    private let slider = NSSlider()
    private let valueLabel = NSTextField(labelWithString: "")
    private var lastWrite: Date = .distantPast

    /// Değer cihaza yazılmalı (kısılmış veya sürükleme bitti).
    var onCommit: ((Float) -> Void)?

    init(value: Float, width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 26))

        slider.minValue = 0
        slider.maxValue = 1
        slider.floatValue = value
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderMoved)
        slider.controlSize = .small
        slider.frame = NSRect(x: 20, y: 3, width: width - 20 - 52, height: 20)
        addSubview(slider)

        valueLabel.alignment = .right
        valueLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.frame = NSRect(x: width - 48, y: 5, width: 36, height: 16)
        addSubview(valueLabel)

        updateLabel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) kullanılmıyor") }

    private func updateLabel() {
        valueLabel.stringValue = "%\(Int((slider.floatValue * 100).rounded()))"
    }

    @objc private func sliderMoved() {
        updateLabel()

        let isDragEnd = NSApp.currentEvent?.type == .leftMouseUp
        let now = Date()
        guard isDragEnd || now.timeIntervalSince(lastWrite) >= Self.writeInterval else { return }

        lastWrite = now
        onCommit?(slider.floatValue)
    }
}
