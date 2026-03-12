import Cocoa

let app = NSApplication.shared
app.setActivationPolicy(.regular) // Show in dock — we're a real app now
let delegate = AppDelegate()
app.delegate = delegate
app.run()
