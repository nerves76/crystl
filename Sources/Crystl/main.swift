import Cocoa

let app = NSApplication.shared
app.setActivationPolicy(.regular) // Show in dock — we're a real app now
let delegate = AppDelegate()
app.delegate = delegate

// ── Main Menu ──
// Required for standard key equivalents (Cmd+C, Cmd+V, Cmd+A, etc.)
// to route through the responder chain to SwiftTerm.

let mainMenu = NSMenu()

// App menu
let appMenuItem = NSMenuItem()
let appMenu = NSMenu()
appMenu.addItem(NSMenuItem(title: "About Crystl", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
appMenu.addItem(NSMenuItem.separator())
appMenu.addItem(NSMenuItem(title: "Quit Crystl", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
appMenuItem.submenu = appMenu
mainMenu.addItem(appMenuItem)

// Edit menu — enables Cmd+C/V/A in SwiftTerm
let editMenuItem = NSMenuItem()
let editMenu = NSMenu(title: "Edit")
editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
editMenuItem.submenu = editMenu
mainMenu.addItem(editMenuItem)

// Window menu
let windowMenuItem = NSMenuItem()
let windowMenu = NSMenu(title: "Window")
windowMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
windowMenu.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
windowMenuItem.submenu = windowMenu
mainMenu.addItem(windowMenuItem)

app.mainMenu = mainMenu
app.run()
