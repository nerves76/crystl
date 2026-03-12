# Crystl

A macOS terminal app with an Apple Glass aesthetic that manages Claude Code permission approvals.

## What it does

Crystl combines a tabbed terminal emulator with a visual permission approval system for [Claude Code](https://claude.ai/claude-code). When Claude Code needs permission to run a tool (edit a file, execute a command, etc.), Crystl shows a floating glass-style card where you can Allow or Deny the action.

### Features

- **Glass terminal** — Translucent, frosted terminal window with rounded corners and inner glow
- **Tabbed sessions** — Multiple terminal tabs, named by working directory, double-click to rename
- **Approval panels** — Floating notification cards for Claude Code permission requests
- **Approval modes** — Manual (approve each), Smart (auto-approve safe tools), Auto (approve all)
- **Claude modes** — Switch between plan, default, acceptEdits, bypassPermissions, auto
- **Pause** — Kill switch that falls through to Claude Code's normal terminal prompts
- **Process notifications** — Cards when a terminal process exits, with Show button to jump to tab
- **Allow All** — Batch-approve when multiple requests are queued
- **Settings popover** — Effort level, default mode, bridge port, link to settings.json

## Architecture

```
Claude Code  --HTTP hook-->  claude-bridge.js  <--HTTP poll--  Crystl.app
                             (Node.js, port 19280)
```

1. **Claude Code** sends a `PermissionRequest` hook via HTTP to the bridge
2. **claude-bridge.js** holds the HTTP connection open and queues the request
3. **Crystl** polls `GET /pending` every 0.5s, shows approval panels
4. User clicks Allow/Deny, Crystl sends `POST /decide`
5. Bridge resolves the held connection, Claude Code proceeds

The bridge also handles auto-approval logic (smart mode checks tool type and permission mode).

### Files

| File | Description |
|------|-------------|
| `Sources/Crystl/main.swift` | App entry point |
| `Sources/Crystl/AppDelegate.swift` | Bridge polling, approval panels, notifications |
| `Sources/Crystl/TerminalWindow.swift` | Glass window, tab bar, terminal views, status bar |
| `Sources/Crystl/Models.swift` | Codable structs matching bridge JSON payloads |
| `Sources/Crystl/Helpers.swift` | Visual helpers, session colors, formatting utilities |
| `claude-bridge.js` | Node.js HTTP server bridging Claude Code and Crystl |
| `build.sh` | Builds Swift package, creates .app bundle, installs LaunchAgent |
| `Package.swift` | Swift Package Manager config (SwiftTerm dependency) |

## Setup

### Prerequisites

- macOS 13+
- Swift 5.9+
- Node.js (for the bridge server)

### Build & Install

```bash
./build.sh
```

This will:
1. Build the Swift package in release mode
2. Create `~/Applications/Crystl.app`
3. Install `claude-bridge.js` as a LaunchAgent (auto-starts on login)

### Configure Claude Code

Add the permission hook to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PermissionRequest": [{
      "matcher": "*",
      "hooks": [{ "type": "http", "url": "http://127.0.0.1:19280/hook" }]
    }]
  }
}
```

### Run

```bash
open ~/Applications/Crystl.app
```

## Bridge API

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/hook` | POST | Claude Code sends permission requests here (connection held until decided) |
| `/pending` | GET | Returns pending requests, sessions, history, and settings |
| `/decide` | POST | Resolve a request: `{ "id": "1", "decision": "allow" }` |
| `/settings` | GET/POST | Read or update bridge settings (mode, paused, session overrides) |

## Approval Modes

| Mode | Behavior |
|------|----------|
| **Manual** | Every permission request requires explicit approval |
| **Smart** | Auto-approves read-only tools; respects Claude's permission mode for edits |
| **Auto** | Approves everything automatically |
| **Pause** | Disables the bridge entirely; Claude Code falls back to terminal prompts |
