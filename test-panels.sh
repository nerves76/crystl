#!/bin/bash
# test-panels.sh — Fire fake permission requests at the bridge to preview panel animations
# Usage: ./test-panels.sh [delay_seconds]
#   delay_seconds: time between panels (default 1.2)

BRIDGE="http://127.0.0.1:19280"
DELAY="${1:-1.2}"

# Check bridge is running
if ! curl -sf "$BRIDGE/health" > /dev/null 2>&1; then
  echo "Bridge not running on $BRIDGE"
  echo "Start it with: node claude-bridge.js"
  exit 1
fi

echo "Sending test panels to Crystl (${DELAY}s between each)..."
echo ""

# ── 1. Bash command ──
echo "→ Panel 1: Bash (rm -rf)"
curl -sf -X POST "$BRIDGE/hook" \
  -H "Content-Type: application/json" \
  -d '{
    "tool_name": "Bash",
    "tool_input": {"command": "rm -rf node_modules && npm install"},
    "cwd": "/Users/chris/projects/webapp",
    "session_id": "sess-alpha-001",
    "permission_mode": "default"
  }' > /dev/null
sleep "$DELAY"

# ── 2. Write file ──
echo "→ Panel 2: Write (new file)"
curl -sf -X POST "$BRIDGE/hook" \
  -H "Content-Type: application/json" \
  -d '{
    "tool_name": "Write",
    "tool_input": {"file_path": "/Users/chris/projects/webapp/src/auth/login.tsx", "content": "..."},
    "cwd": "/Users/chris/projects/webapp",
    "session_id": "sess-alpha-001",
    "permission_mode": "default"
  }' > /dev/null
sleep "$DELAY"

# ── 3. Edit from different session ──
echo "→ Panel 3: Edit (different session)"
curl -sf -X POST "$BRIDGE/hook" \
  -H "Content-Type: application/json" \
  -d '{
    "tool_name": "Edit",
    "tool_input": {"file_path": "/Users/chris/Nextcloud/crystl/Sources/Crystl/AppDelegate.swift", "old_string": "func poll()", "new_string": "func pollBridge()"},
    "cwd": "/Users/chris/Nextcloud/crystl",
    "session_id": "sess-beta-002",
    "permission_mode": "acceptEdits"
  }' > /dev/null
sleep "$DELAY"

# ── 4. Bash from third session ──
echo "→ Panel 4: Bash (git push, third session)"
curl -sf -X POST "$BRIDGE/hook" \
  -H "Content-Type: application/json" \
  -d '{
    "tool_name": "Bash",
    "tool_input": {"command": "git push origin main --force"},
    "cwd": "/Users/chris/projects/api-server",
    "session_id": "sess-gamma-003",
    "permission_mode": "plan"
  }' > /dev/null
sleep "$DELAY"

# ── 5. WebFetch ──
echo "→ Panel 5: WebFetch"
curl -sf -X POST "$BRIDGE/hook" \
  -H "Content-Type: application/json" \
  -d '{
    "tool_name": "WebFetch",
    "tool_input": {"url": "https://api.example.com/v2/deploy?env=production"},
    "cwd": "/Users/chris/projects/webapp",
    "session_id": "sess-alpha-001",
    "permission_mode": "default"
  }' > /dev/null
sleep "$DELAY"

# ── 6. Dangerous Bash ──
echo "→ Panel 6: Bash (database drop)"
curl -sf -X POST "$BRIDGE/hook" \
  -H "Content-Type: application/json" \
  -d '{
    "tool_name": "Bash",
    "tool_input": {"command": "psql -c \"DROP TABLE users CASCADE\""},
    "cwd": "/Users/chris/projects/api-server",
    "session_id": "sess-gamma-003",
    "permission_mode": "default"
  }' > /dev/null

echo ""
echo "Done! 6 panels sent. They will timeout after 60s if not dismissed."
echo "Click Allow/Deny to dismiss, or wait for expiry."
