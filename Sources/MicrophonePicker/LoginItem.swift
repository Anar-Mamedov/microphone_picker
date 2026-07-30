import Foundation
import ServiceManagement

/// "Girişte başlat" ayarı için `SMAppService` sarmalayıcısı.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Açıksa kapatır, kapalıysa açar. Başarısız olursa hata mesajı döner.
    static func toggle() -> String? {
        do {
            if isEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
