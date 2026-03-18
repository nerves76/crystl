# Crystl

macOS terminal app with floating approval panels for Claude Code. Built with AppKit + SwiftTerm (no SwiftUI).

## Build & Run

```bash
cd /Users/chris/Nextcloud/crystl
swift build -c release          # compile
bash build.sh                   # compile + install to ~/Applications + register services + restart bridge
killall Crystl; open ~/Applications/Crystl.app  # restart after install
CRYSTL_DEV=1 open ~/Applications/Crystl.app     # run with dev mode (bypasses license checks)
```

## Architecture

```
main.swift              Entry point, NSApplication setup, main menu
AppDelegate.swift       App lifecycle, bridge polling, approval/notification panels
TerminalWindow.swift    Window, gem bar, gem/shard management, settings flip, terminal config, click-to-open
TerminalSession.swift   TerminalSession (shard), ProjectTab (gem), InsetFrostView, GlowButton, TerminalDropView
TabBarView.swift        TabBarView (gem tabs) + SessionBarView (shard bar)
CrystalRail.swift       Screen-edge glass rail: tiles, add button, new gem panel
GitWorktree.swift       Git worktree management for isolated shards
DirectoryPicker.swift   Warp-style directory chooser overlay for new tabs
CommandHistory.swift    Shell integration (ZDOTDIR injection) + OSC 7770 command logger + API key injection
SettingsView.swift      Settings panel (sidebar nav, 7 pages), GlassToggle, StarterEditorPanel
LicenseManager.swift    License validation, Guild membership tier
ShardPickerView.swift   Shard picker overlay for split panes
SplitViewController.swift  Split pane layout controller
APIKeyStore.swift       Secure API key storage via macOS Keychain
ProjectConfig.swift     Per-project config (.crystl/project.json): name, icon, color
MCPConfig.swift         MCP server catalog management
StarterManager.swift    Starter file templates (~/.config/crystl/starters.json)
LucideIconData.swift    Bundled Lucide icon SVG data (133 icons including gem/crystal set)
LucideIcons.swift       SVG-to-NSImage renderer for Lucide icons
IconPickerView.swift    Icon and color picker panels for gems
AgentDetector.swift     Agent detection (Claude Code, Codex) via terminal process tree
Models.swift            JSON data types for bridge communication
Helpers.swift           Shared utilities: colors, mask images, session color map
```

### Communication Flow

```
Claude Code --> HTTP hook --> claude-bridge.js (holds connection, port 19280)
Crystl polls GET /pending --> shows approval panel --> user clicks Allow/Deny/Always
Crystl sends POST /decide --> bridge resolves the held connection
```

### Key Patterns

- **Glass aesthetic**: All panels use `NSVisualEffectView` with `.hudWindow` material, `.darkAqua` appearance, `roundedMaskImage()` for corners
- **Non-activating panels**: Floating notifications use `.nonactivatingPanel` + `.borderless` so they don't steal focus. Settings/input panels use `.titled` so they can accept keyboard input.
- **Animation**: `animateLiquidCrystal()` in AppDelegate for panel open effects. `CATransition(type: "flip")` for settings flip. Tile pulse uses `CABasicAnimation` on border + scale.
- **Gem ↔ Rail sync**: `TerminalWindowController` fires `onTabAdded/Removed/Selected/Updated` callbacks. `AppDelegate` wires these to `CrystalRailController` methods.
- **Shell integration**: `ShellIntegration` overrides ZDOTDIR to inject zsh hooks that emit OSC 7770 sequences for command history tracking.
- **Click-to-open**: Clicking on file paths in terminal output opens them in the default editor. Drag or multi-click is ignored (text selection still works normally).

### Approval Panels

Floating glass panels that appear when Claude Code requests tool permission. Three buttons plus one modifier shortcut cover all Claude Code permission behaviors:

| Button | Decision | Behavior |
|--------|----------|----------|
| **Allow** | `allow` | Approve this one tool use |
| **Always** | `allowAlways` | Approve and don't ask again (writes to local settings via `updatedPermissions`) |
| **Deny** | `deny` | Reject this tool use |
| **Option+Deny** | `abort` | Stop the entire Claude session |

- **Allow** (green) is the default button (Enter key)
- **Always** (blue) echoes back `permission_suggestions` from the request as `updatedPermissions` with `destination: 'localSettings'`
- **Option+Deny** is a hidden power-user shortcut — no visible UI, detected via `NSApp.currentEvent?.modifierFlags.contains(.option)`
- Hooks only fire inside Crystl terminals (guarded by `$TERM_PROGRAM = Crystl` in command-type hooks)

### Shards (Sub-tabs)

Each **gem** (project tab) can have multiple **shards** — terminal sessions within the same project. Shards are named after crystals: diamond, aquamarine, sapphire, tanzanite, amethyst, emerald, peridot, citrine, carnelian, ruby. Each crystal has a signature color used for the shard label text and underline accent.

- Shards appear in the **shard bar** below the tab bar (visible when 2+ shards exist)
- Click "+" to add a shared shard (same working directory)
- **Option+click "+"** to add an **isolated shard** backed by a git worktree

### Isolated Shards (Git Worktrees)

Isolated shards let multiple agents work on the same project without conflicts. Each isolated shard gets its own git worktree — a full working copy on a separate branch.

```
Project: ~/Projects/myapp (main branch)
├── diamond     — main working directory (shared)
├── ⎇ aquamarine — .crystl/worktrees/aquamarine (branch: crystl/aquamarine)
└── ⎇ sapphire  — .crystl/worktrees/sapphire   (branch: crystl/sapphire)
```

**How it works:**
- `GitWorktree.create()` runs `git worktree add -b crystl/{name} .crystl/worktrees/{name}`
- Untracked config files are symlinked into the worktree: `CLAUDE.md`, `AGENTS.md`, `.mcp.json`, `.claude/`
- The shard bar shows a `⎇` prefix on isolated shards
- The shell starts `cd`'d into the worktree path

**On close:**
- If the branch has no unique commits → worktree and branch are both removed
- If commits exist → worktree is removed but **branch is kept** (work preserved)
- `cleanupWorktree()` is called from both `closeSession()` and `closeProject()`

**Error handling:**
- Not a git repo → red error in terminal, no shard created
- Worktree creation failed → yellow warning, falls back to shared shard
- Success → cyan message showing branch name

**Safety:**
- `.crystl/` is gitignored — worktrees don't appear in `git status`
- Stale worktrees are force-cleaned before reuse
- Non-git projects get a normal shard (no worktree)
- Starter files skip existing files (no overwrites)
- MCP `.mcp.json` merges with existing config (preserves manual servers)
- ProjectConfig merges on save (name/icon/color don't clobber each other)

### Click-to-Open File Paths

Clicking on a file path in the terminal opens it in the system default editor.

**How it works:**
- `NSEvent.addLocalMonitorForEvents` watches for mouse down/drag/up on terminal views
- On clean single click (no drag, no double-click), extracts the row text via `terminal.getLine(row:).translateToString()`
- Walks left/right from the click column to extract a path-like token (characters: `a-z 0-9 / . ~ _ - + @ :`)
- Strips trailing `:line:col` suffixes (e.g. `file.swift:42:10` → `file.swift`)
- Resolves relative paths against the session's cwd
- Only opens if `FileManager.default.fileExists(atPath:)` — no false positives
- Uses `NSWorkspace.shared.open()` to open with the system default editor

**Filtering:**
- Must contain a `/` or a file extension (`.swift`, `.md`, etc.) to be considered a path
- Drag of 3+ pixels cancels the click (text selection)
- Double/triple clicks are ignored (word/line selection)

### Settings Sidebar

Settings uses a Warp-style sidebar navigation with 7 pages: **General**, **Claude**, **Codex**, **MCP Servers**, **Starter Files**, **API Keys**, **License**.

- Sidebar width: 200px, top padding 52px (clears traffic lights)
- Content area: top padding 100px (below "Settings" title)
- Each page built by `build{Page}Page()` returning an NSView inside a scroll view
- `finalizeDocView()` trims doc views and pins content at top

### Guild Membership

The paid tier is called **Guild**. Status bar shows "GUILD" or "FREE". License page shows "GUILD MEMBER" when active. The API Keys page shows a "Join the Guild!" callout box (outlined border, diamond bullet list of benefits) when unlicensed.

### API Keys

API keys for AI providers are stored securely in macOS Keychain and injected as environment variables into every new terminal session.

**Supported providers:**
| Provider | Environment Variable | Placeholder |
|----------|---------------------|-------------|
| Anthropic | `ANTHROPIC_API_KEY` | `sk-ant-...` |
| OpenAI | `OPENAI_API_KEY` | `sk-...` |
| Google AI | `GEMINI_API_KEY` | `AIza...` |
| OpenRouter | `OPENROUTER_API_KEY` | `sk-or-...` |

**Storage:** `APIKeyStore` uses `Security.framework` Keychain APIs under service `com.crystl.api-keys`. Keys are never stored in UserDefaults or on disk in plain text.

**Injection:** `ShellIntegration.environment()` calls `APIKeyStore.shared.allKeys()` and merges into the process environment. Existing env vars take precedence — if a key is already set in the user's shell profile, Crystl won't override it.

**Settings UI:** Secure text fields (bullets) with masked placeholders for saved keys (e.g. `sk-ant••••••ab3f`). Field clears after saving. New sessions pick up keys immediately; existing sessions need restart.

### GlassToggle

`GlassToggle` is a custom iOS-style toggle switch used for toggles in settings.

- Rounded track: icy blue (`rgba(0.55, 0.72, 0.85, 0.6)`) when on, glass (`white alpha 0.12`) when off
- White circular knob slides with 0.2s ease animation
- Label text to the right of the track
- `mouseDown` toggles state and fires target/action
- `.state` property returns `NSControl.StateValue` for compatibility with existing handlers

### Lucide Icons

133 bundled Lucide icons including a gem/crystal set. Gem-related icons added:

`gem`, `diamond`, `diamond-plus`, `diamond-minus`, `diamond-percent`, `crown`, `hexagon`, `octagon`, `pentagon`, `pyramid`, `sparkle`, `sparkles`, `triangle`

Icon data lives in `LucideIconData.swift` as SVG inner elements. `LucideIcons.swift` renders them to `NSImage` at any size/color.

## File Size Limits

Keep source files under **500 lines**. Current violations:

- `SettingsView.swift` (2,045 lines) — split out: per-page builders into separate files
- `AppDelegate.swift` (1,429 lines) — split out: `ApprovalPanel.swift`, shared animation code
- `CrystalRail.swift` (1,403 lines) — split out: `NewProjectPanel`, tile management
- `TerminalWindow.swift` (1,091 lines) — split out: terminal config/appearance helpers

## Code Conventions

- Each file starts with `// FileName.swift — one-line description` then a comment block explaining what's inside
- Use `// MARK: -` sections within files
- Use `// ── Section Name ──` for visual separators in long setup methods
- `[weak self]` in all closures that capture `self` and outlive the call (callbacks, animation completions, async)
- `?.` optional chaining for the `rail` property and any optional controller references
- Shell commands sent to terminal must use `shellEscape()` (single-quote wrapping)

## UI Style Guide

### Corner Radii
- **12px** — containers, panels, overlays, search fields (DirectoryPicker, glass panels)
- **8px** — input fields, buttons, controls (settings fields, Browse button, popup buttons)
- **16px** — window `contentView` corner radius
- Always set `layer?.masksToBounds = true` when using `cornerRadius` on NSTextField (otherwise background won't clip)

### Spacing (Settings / Forms)
- `sectionToHeader: 16` — section header to first field label
- `labelToControl: 16` — field label to its control
- `controlToLabel: 10` — control to next field label
- `sectionBreak: 20` — control to next section header
- `labelH: 14` — label text height
- `controlH: 28` — standard control height (fields, buttons, popups)

### Typography
- **Window title**: 22pt semibold
- **Section headers**: 10pt bold, uppercase (e.g. "GENERAL", "CLAUDE")
- **Field labels**: 9pt semibold, uppercase (e.g. "BRIDGE PORT")
- **Body / field text**: 12pt mono regular
- **Tab bar titles**: 11.5pt mono
- **Directory picker rows**: 14pt system, medium weight for folders, regular for files

### Colors
- **Section headers / field labels**: `white alpha 0.7`
- **Body text**: `white`
- **Secondary / dim text**: `white alpha 0.5`
- **Hint / subtle UI text**: `white alpha 0.6` (shard hints, secondary buttons, small labels)
- **Empty state text**: `white alpha 0.35`
- **Field backgrounds**: `white alpha 0.12`
- **Button tint (secondary)**: `white alpha 0.6`
- **Borders**: `white alpha 0.15–0.3`

### Glass Panels
- Material: `.hudWindow`
- Appearance: `.darkAqua`
- Blending: `.behindWindow`
- State: `.active`
- Never use solid opaque backgrounds — preserve transparency
- **All windows/panels must share the same background opacity.** The opacity slider (`windowOpacity` UserDefaults) must affect every surface: terminal window, Crystal Rail, New Gem panel, approval panels, notification panels, shard picker, and any future panels. When a new panel is created, read the saved opacity and apply it. When the slider moves, update all visible surfaces.

### General Rules
- Non-flipped NSView coordinates: y increases upward. Label-to-control gap must be >= `controlH - labelH` to prevent overlap.
- Use `layer?.opacity = 0` (not just `isHidden = true`) to prevent layer content bleeding through glass effects.
- Z-order for clickable areas: add the visual label first, then the transparent click target on top.
- Animations: use fluid timing `CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)` for open/slide effects.

## Known Issues / Tech Debt

- **KVO leak**: `makeTerminalTransparent` adds observer on `layer.backgroundColor` but never removes it. Fix: switch to block-based KVO and store in `scrollerObservers`.
- **Thread safety**: `CommandHistoryLogger.pending` and `initializedDirs` accessed from multiple threads. `hostCurrentDirectoryUpdate` doesn't dispatch to main.
- **Retain cycles**: Animation completion handlers in AppDelegate capture `self` strongly. `NewProjectPanel` field → target → self cycle.
- **Bridge auth**: No authentication on localhost HTTP — any local process can send `/decide`. Should add a shared token.
- **Temp files**: ZDOTDIR proxy files in `/tmp/crystl-shell-{pid}/` never cleaned up.
- **DRY**: Glass panel construction repeated 3x in AppDelegate. `animateLiquidCrystal` duplicated between AppDelegate and TerminalWindow.

### New Gem Panel

The New Gem panel (from rail "+" or "Gem Settings" button) includes:
- **Name** — gem display name, saved to `.crystl/project.json`
- **Path** — parent directory (editable for new, read-only for existing gems)
- **Initialize git** checkbox — runs `git init` on create (checked by default, hidden for existing)
- **Remote URL** — auto-fills from base URL + project name, runs `git remote add origin`
- **Color** / **Icon** pickers
- **MCP servers** — checkboxes from catalog, merged into `.mcp.json`
- **Starter files** — checkboxes from templates, skip existing files

## Settings

- `projectsDirectory` — UserDefaults. Base directory for new gems. Default: `~/Projects`.
- `gitRemoteBaseUrl` — UserDefaults. Base URL for git remotes (e.g. `git@github.com:user/`). Auto-fills remote field in New Gem panel as `{baseUrl}{name}.git`.
- `agentEnabled:claude` / `agentEnabled:codex` — UserDefaults (Bool). Enable/disable agent sections in settings. Claude defaults to `true`, Codex to `false`. Uses `GlassToggle` UI.
- `crystalRailEnabled` — UserDefaults (Bool). Show/hide the Crystal Rail. Default: `true`.
- `crystalRailSide` — UserDefaults (String). Which screen edge for the rail and floating panels: `"left"` or `"right"`. Default: `"left"`.
- `notificationsEnabled` — UserDefaults (Bool). Show/hide floating notification panels. Default: `true`.
- API keys — Keychain (`com.crystl.api-keys`). `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY`, `OPENROUTER_API_KEY`. Injected into terminal sessions via `ShellIntegration.environment()`.
- Bridge port `19280` — hardcoded in AppDelegate and build.sh.
- Shell prompt is not overridden — user's own zsh config applies.

## Dependencies

- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) — terminal emulator
- [swift-argument-parser](https://github.com/apple/swift-argument-parser) — CLI argument parsing
- `claude-bridge.js` — Node.js HTTP server that mediates between Claude Code hooks and Crystl
