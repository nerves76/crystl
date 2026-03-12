# Crystl

macOS terminal app with floating approval panels for Claude Code. Built with AppKit + SwiftTerm (no SwiftUI).

## Build & Run

```bash
cd /Users/chris/Nextcloud/crystl
swift build -c release          # compile
bash build.sh                   # compile + install to ~/Applications + register services + restart bridge
killall Crystl; open ~/Applications/Crystl.app  # restart after install
```

## Architecture

```
main.swift              Entry point, NSApplication setup, main menu
AppDelegate.swift       App lifecycle, bridge polling, approval/notification panels
TerminalWindow.swift    Window, tab bar, tab management, settings flip, terminal config
CrystalRail.swift       Screen-edge glass rail: tiles, add button, new project panel
DirectoryPicker.swift   Warp-style directory chooser overlay for new tabs
CommandHistory.swift    Shell integration (ZDOTDIR injection) + OSC 7770 command logger
Models.swift            JSON data types for bridge communication
Helpers.swift           Shared utilities: colors, mask images, session color map
```

### Communication Flow

```
Claude Code --> HTTP hook --> claude-bridge.js (holds connection, port 19280)
Crystl polls GET /pending --> shows approval panel --> user clicks Allow/Deny
Crystl sends POST /decide --> bridge resolves the held connection
```

### Key Patterns

- **Glass aesthetic**: All panels use `NSVisualEffectView` with `.hudWindow` material, `.darkAqua` appearance, `roundedMaskImage()` for corners
- **Non-activating panels**: Floating notifications use `.nonactivatingPanel` + `.borderless` so they don't steal focus. Settings/input panels use `.titled` so they can accept keyboard input.
- **Animation**: `animateLiquidCrystal()` in AppDelegate for panel open effects. `CATransition(type: "flip")` for settings flip. Tile pulse uses `CABasicAnimation` on border + scale.
- **Tab ↔ Rail sync**: `TerminalWindowController` fires `onTabAdded/Removed/Selected/Updated` callbacks. `AppDelegate` wires these to `CrystalRailController` methods.
- **Shell integration**: `ShellIntegration` overrides ZDOTDIR to inject zsh hooks that emit OSC 7770 sequences for command history tracking.

## File Size Limits

Keep source files under **500 lines**. Current violations to address:

- `TerminalWindow.swift` (1,219 lines) — split out: `TerminalTab.swift`, `TabBarView.swift`, `SettingsView.swift`
- `AppDelegate.swift` (859 lines) — split out: `ApprovalPanel.swift`, shared animation code
- `CrystalRail.swift` (702 lines) — acceptable for now, tightly coupled classes

## Code Conventions

- Each file starts with `// FileName.swift — one-line description` then a comment block explaining what's inside
- Use `// MARK: -` sections within files
- Use `// ── Section Name ──` for visual separators in long setup methods
- `[weak self]` in all closures that capture `self` and outlive the call (callbacks, animation completions, async)
- `?.` optional chaining for the `rail` property and any optional controller references
- Shell commands sent to terminal must use `shellEscape()` (single-quote wrapping)

## Known Issues / Tech Debt

- **KVO leak**: `makeTerminalTransparent` adds observer on `layer.backgroundColor` but never removes it. Fix: switch to block-based KVO and store in `scrollerObservers`.
- **Thread safety**: `CommandHistoryLogger.pending` and `initializedDirs` accessed from multiple threads. `hostCurrentDirectoryUpdate` doesn't dispatch to main.
- **Retain cycles**: Animation completion handlers in AppDelegate capture `self` strongly. `NewProjectPanel` field → target → self cycle.
- **Bridge auth**: No authentication on localhost HTTP — any local process can send `/decide`. Should add a shared token.
- **Temp files**: ZDOTDIR proxy files in `/tmp/crystl-shell-{pid}/` never cleaned up.
- **DRY**: Glass panel construction repeated 3x in AppDelegate. `animateLiquidCrystal` duplicated between AppDelegate and TerminalWindow.

## Settings

- `projectsDirectory` — UserDefaults key for the base directory used by DirectoryPicker and NewProjectPanel. Default: `~/Projects`.
- Bridge port `19280` — hardcoded in AppDelegate and build.sh.
- Shell prompt set to minimal `› ` in `CommandHistory.swift` integration script.

## Dependencies

- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) — terminal emulator
- [swift-argument-parser](https://github.com/apple/swift-argument-parser) — CLI argument parsing
- `claude-bridge.js` — Node.js HTTP server that mediates between Claude Code hooks and Crystl
