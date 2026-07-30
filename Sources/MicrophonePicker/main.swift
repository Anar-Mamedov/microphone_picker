import AppKit

let application = NSApplication.shared
let delegate = AppDelegate()

application.delegate = delegate
// Dock simgesi yok, yalnızca menü çubuğu.
application.setActivationPolicy(.accessory)
application.run()
