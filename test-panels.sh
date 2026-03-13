#!/bin/bash
# test-panels.sh — Fire fake requests at the bridge to preview all panel types
# Usage: ./test-panels.sh [delay_seconds]
#   delay_seconds: time between panels (default 1.5)

BRIDGE="http://127.0.0.1:19280"
DELAY="${1:-1.5}"

# Check bridge is running
if ! curl -sf "$BRIDGE/health" > /dev/null 2>&1; then
  echo "Bridge not running on $BRIDGE"
  echo "Start it with: node claude-bridge.js"
  exit 1
fi

echo "Sending test panels to Crystl (${DELAY}s between each)..."
echo ""

# ══════════════════════════════════════════
# APPROVAL PANELS (PermissionRequest)
# ══════════════════════════════════════════

echo "── Approval Panels ──"

echo "→ Bash (rm -rf)"
curl -sf -X POST "$BRIDGE/hook?type=PermissionRequest" \
  -H "Content-Type: application/json" \
  -d '{
    "tool_name": "Bash",
    "tool_input": {"command": "rm -rf node_modules && npm install"},
    "cwd": "/Users/chris/projects/webapp",
    "session_id": "sess-alpha-001",
    "permission_mode": "default"
  }' > /dev/null &
sleep "$DELAY"

echo "→ Write (new file)"
curl -sf -X POST "$BRIDGE/hook?type=PermissionRequest" \
  -H "Content-Type: application/json" \
  -d '{
    "tool_name": "Write",
    "tool_input": {"file_path": "/Users/chris/projects/webapp/src/auth/login.tsx", "content": "..."},
    "cwd": "/Users/chris/projects/webapp",
    "session_id": "sess-alpha-001",
    "permission_mode": "default"
  }' > /dev/null &
sleep "$DELAY"

echo "→ Edit (different session)"
curl -sf -X POST "$BRIDGE/hook?type=PermissionRequest" \
  -H "Content-Type: application/json" \
  -d '{
    "tool_name": "Edit",
    "tool_input": {"file_path": "Sources/Crystl/AppDelegate.swift", "old_string": "func poll()", "new_string": "func pollBridge()"},
    "cwd": "/Users/chris/Nextcloud/crystl",
    "session_id": "sess-beta-002",
    "permission_mode": "acceptEdits"
  }' > /dev/null &
sleep "$DELAY"

# ══════════════════════════════════════════
# NOTIFICATIONS (fire-and-forget)
# ══════════════════════════════════════════

echo ""
echo "── Notification Panels ──"

echo "→ Stop: Claude finished"
curl -sf -X POST "$BRIDGE/hook?type=Stop" \
  -H "Content-Type: application/json" \
  -d '{
    "session_id": "sess-alpha-001",
    "cwd": "/Users/chris/projects/webapp",
    "last_assistant_message": "I'\''ve finished refactoring the auth module. All tests pass and the login flow now uses JWT tokens with refresh rotation.",
    "stop_hook_active": true
  }' > /dev/null
sleep "$DELAY"

echo "→ PostToolUse: Edit completed"
curl -sf -X POST "$BRIDGE/hook?type=PostToolUse" \
  -H "Content-Type: application/json" \
  -d '{
    "session_id": "sess-beta-002",
    "cwd": "/Users/chris/Nextcloud/crystl",
    "tool_name": "Edit",
    "tool_input": {"file_path": "Sources/Crystl/AppDelegate.swift"},
    "tool_response": "Successfully edited AppDelegate.swift (3 lines changed)"
  }' > /dev/null
sleep "$DELAY"

echo "→ SubagentStop: Agent finished"
curl -sf -X POST "$BRIDGE/hook?type=SubagentStop" \
  -H "Content-Type: application/json" \
  -d '{
    "session_id": "sess-alpha-001",
    "cwd": "/Users/chris/projects/webapp",
    "agent_id": "agent-explore-42",
    "agent_type": "Explore",
    "last_assistant_message": "Found 3 files matching the pattern: UserService.ts, AuthController.ts, and SessionManager.ts"
  }' > /dev/null
sleep "$DELAY"

echo "→ TaskCompleted: Task done"
curl -sf -X POST "$BRIDGE/hook?type=TaskCompleted" \
  -H "Content-Type: application/json" \
  -d '{
    "session_id": "sess-alpha-001",
    "cwd": "/Users/chris/projects/webapp",
    "task_id": "task-17",
    "task_subject": "Add rate limiting to /api/login endpoint",
    "teammate_name": "backend-agent",
    "team_name": "webapp-team"
  }' > /dev/null
sleep "$DELAY"

echo "→ Notification: Idle prompt"
curl -sf -X POST "$BRIDGE/hook?type=Notification" \
  -H "Content-Type: application/json" \
  -d '{
    "session_id": "sess-beta-002",
    "cwd": "/Users/chris/Nextcloud/crystl",
    "title": "Waiting for input",
    "message": "Claude is waiting for your response in the crystl project",
    "notification_type": "idle_prompt"
  }' > /dev/null
sleep "$DELAY"

echo "→ TeammateIdle: Agent idle"
curl -sf -X POST "$BRIDGE/hook?type=TeammateIdle" \
  -H "Content-Type: application/json" \
  -d '{
    "session_id": "sess-alpha-001",
    "cwd": "/Users/chris/projects/webapp",
    "teammate_name": "frontend-agent",
    "team_name": "webapp-team"
  }' > /dev/null
sleep "$DELAY"

echo "→ SessionEnd: Session ended"
curl -sf -X POST "$BRIDGE/hook?type=SessionEnd" \
  -H "Content-Type: application/json" \
  -d '{
    "session_id": "sess-gamma-003",
    "cwd": "/Users/chris/projects/api-server",
    "reason": "prompt_input_exit"
  }' > /dev/null
sleep "$DELAY"

echo "→ Stop: Another session finished"
curl -sf -X POST "$BRIDGE/hook?type=Stop" \
  -H "Content-Type: application/json" \
  -d '{
    "session_id": "sess-beta-002",
    "cwd": "/Users/chris/Nextcloud/crystl",
    "last_assistant_message": "Done! The notification system is working. I added support for Stop, PostToolUse, SubagentStop, TaskCompleted, Notification, TeammateIdle, and SessionEnd hook types.",
    "stop_hook_active": true
  }' > /dev/null
sleep "$DELAY"

echo "→ Notification: Auth success"
curl -sf -X POST "$BRIDGE/hook?type=Notification" \
  -H "Content-Type: application/json" \
  -d '{
    "session_id": "sess-alpha-001",
    "cwd": "/Users/chris/projects/webapp",
    "title": "Authentication successful",
    "message": "API key validated, resuming session",
    "notification_type": "auth_success"
  }' > /dev/null

echo ""
echo "Done! 3 approval panels + 9 notifications sent."
echo "Approval panels timeout after 60s. Notifications auto-dismiss after 8s."
