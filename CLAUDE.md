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
TerminalWindow.swift    Window, crystal bar, crystal/shard management, settings flip, terminal config
TerminalSession.swift   TerminalSession (shard), ProjectTab (crystal), InsetFrostView, GlowButton, TerminalDropView
TabBarView.swift        TabBarView (crystal tabs) + SessionBarView (shard bar)
CrystalRail.swift       Screen-edge glass rail: tiles, add button, new crystal panel
GitWorktree.swift       Git worktree management for isolated shards
DirectoryPicker.swift   Warp-style directory chooser overlay for new tabs
CommandHistory.swift    Shell integration (ZDOTDIR injection) + OSC 7770 command logger
SettingsView.swift      Settings panel, StarterEditorPanel
ProjectConfig.swift     Per-project config (.crystl/project.json): name, icon, color
MCPConfig.swift         MCP server catalog management
StarterManager.swift    Starter file templates (~/.config/crystl/starters.json)
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
- **Crystal ↔ Rail sync**: `TerminalWindowController` fires `onTabAdded/Removed/Selected/Updated` callbacks. `AppDelegate` wires these to `CrystalRailController` methods.
- **Shell integration**: `ShellIntegration` overrides ZDOTDIR to inject zsh hooks that emit OSC 7770 sequences for command history tracking.

### Shards (Sub-tabs)

Each **crystal** (project tab) can have multiple **shards** — terminal sessions within the same project. Shards are named after crystals: diamond, aquamarine, sapphire, tanzanite, amethyst, emerald, peridot, citrine, carnelian, ruby. Each crystal has a signature color used for the shard label text and underline accent.

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

## File Size Limits

Keep source files under **500 lines**. `TabBarView.swift`, `SettingsView.swift`, `TerminalSession.swift` have been split out. Remaining violations:

- `TerminalWindow.swift` — split out: terminal config/appearance helpers
- `AppDelegate.swift` — split out: `ApprovalPanel.swift`, shared animation code
- `CrystalRail.swift` — acceptable for now, tightly coupled classes

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

### New Crystal Panel

The New Crystal panel (from rail "+" or "Crystal Settings" button) includes:
- **Name** — crystal display name, saved to `.crystl/project.json`
- **Path** — parent directory (editable for new, read-only for existing crystals)
- **Initialize git** checkbox — runs `git init` on create (checked by default, hidden for existing)
- **Remote URL** — auto-fills from base URL + project name, runs `git remote add origin`
- **Color** / **Icon** pickers
- **MCP servers** — checkboxes from catalog, merged into `.mcp.json`
- **Starter files** — checkboxes from templates, skip existing files

## Settings

- `projectsDirectory` — base directory for new crystals. Default: `~/Projects`.
- `gitRemoteBaseUrl` — base URL for git remotes (e.g. `git@github.com:user/`). Auto-fills remote field in New Project panel as `{baseUrl}{name}.git`.
- Bridge port `19280` — hardcoded in AppDelegate and build.sh.
- Shell prompt is not overridden — user's own zsh config applies.

## Dependencies

- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) — terminal emulator
- [swift-argument-parser](https://github.com/apple/swift-argument-parser) — CLI argument parsing
- `claude-bridge.js` — Node.js HTTP server that mediates between Claude Code hooks and Crystl
