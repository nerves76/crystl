import Cocoa
import CrystlLib

let app = NSApplication.shared
app.setActivationPolicy(.regular) // Show in dock — we're a real app now
let delegate = AppDelegate()
app.delegate = delegate

// Prevent macOS from auto-adding Dictation / Emoji & Symbols to Edit menu
UserDefaults.standard.set(true, forKey: "NSDisabledDictationMenuItem")
UserDefaults.standard.set(true, forKey: "NSDisabledCharacterPaletteMenuItem")

// ── Main Menu ──
// Required for standard key equivalents (Cmd+C, Cmd+V, Cmd+A, etc.)
// to route through the responder chain to SwiftTerm.

let mainMenu = NSMenu()

// Helper to create a menu item targeting the delegate
func item(_ title: String, action: Selector, key: String = "", mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
    let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
    mi.target = delegate
    mi.keyEquivalentModifierMask = mods
    return mi
}

// ── App menu ──
let appMenuItem = NSMenuItem()
let appMenu = NSMenu()
appMenu.addItem(NSMenuItem(title: "About Crystl", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
appMenu.addItem(NSMenuItem.separator())
appMenu.addItem(item("Settings…", action: #selector(AppDelegate.showSettings), key: ","))
appMenu.addItem(NSMenuItem.separator())
appMenu.addItem(NSMenuItem(title: "Hide Crystl", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
let hideOthers = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
hideOthers.keyEquivalentModifierMask = [.command, .option]
appMenu.addItem(hideOthers)
appMenu.addItem(NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
appMenu.addItem(NSMenuItem.separator())
appMenu.addItem(NSMenuItem(title: "Quit Crystl", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
appMenuItem.submenu = appMenu
mainMenu.addItem(appMenuItem)

// ── Shell menu ──
let shellMenuItem = NSMenuItem()
let shellMenu = NSMenu(title: "Shell")
shellMenu.addItem(item("New Tab", action: #selector(AppDelegate.newTab), key: "t"))
shellMenu.addItem(item("Close Tab", action: #selector(AppDelegate.closeTab), key: "w"))
shellMenu.addItem(NSMenuItem.separator())
shellMenu.addItem(item("Split Pane", action: #selector(AppDelegate.splitPane), key: "d"))
shellMenu.addItem(NSMenuItem.separator())
shellMenu.addItem(item("Next Tab", action: #selector(AppDelegate.selectNextTab), key: "]", mods: [.command, .shift]))
shellMenu.addItem(item("Previous Tab", action: #selector(AppDelegate.selectPreviousTab), key: "[", mods: [.command, .shift]))
shellMenuItem.submenu = shellMenu
mainMenu.addItem(shellMenuItem)

// ── Edit menu — enables Cmd+C/V/A in SwiftTerm ──
let editMenuItem = NSMenuItem()
let editMenu = NSMenu(title: "Edit")
editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
editMenuItem.submenu = editMenu
mainMenu.addItem(editMenuItem)

// ── View menu ──
let viewMenuItem = NSMenuItem()
let viewMenu = NSMenu(title: "View")
let fullScreen = NSMenuItem(title: "Toggle Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
fullScreen.keyEquivalentModifierMask = [.command, .control]
viewMenu.addItem(fullScreen)
viewMenuItem.submenu = viewMenu
mainMenu.addItem(viewMenuItem)

// ── Window menu ──
let windowMenuItem = NSMenuItem()
let windowMenu = NSMenu(title: "Window")
windowMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
windowMenu.addItem(NSMenuItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
windowMenu.addItem(NSMenuItem.separator())
windowMenu.addItem(NSMenuItem(title: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: ""))
windowMenuItem.submenu = windowMenu
mainMenu.addItem(windowMenuItem)
app.windowsMenu = windowMenu

// ── Help menu ──
let helpMenuItem = NSMenuItem()
let helpMenu = NSMenu(title: "Help")
helpMenu.addItem(item("Crystl Help", action: #selector(AppDelegate.openHelp), key: "?"))
helpMenuItem.submenu = helpMenu
mainMenu.addItem(helpMenuItem)
app.helpMenu = helpMenu

app.mainMenu = mainMenu
app.run()
