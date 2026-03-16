#!/usr/bin/env node
// Claude Code <-> Crystl Bridge Server
// Receives PermissionRequest hooks from Claude Code via HTTP
// Crystl polls for pending requests and sends decisions via HTTP

const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const os = require('os');

const PORT = parseInt(process.env.CLAUDE_BRIDGE_PORT || '19280', 10);
const TIMEOUT_MS = 60000; // 60s before falling through to normal prompt

// ── Auth Token ──
// Generate a random bearer token on startup and write it to ~/.crystl-bridge-token
// so the Crystl app (and only it) can authenticate with the bridge.
const TOKEN_PATH = path.join(os.homedir(), '.crystl-bridge-token');
const AUTH_TOKEN = crypto.randomBytes(32).toString('hex');
fs.writeFileSync(TOKEN_PATH, AUTH_TOKEN + '\n', { mode: 0o600 });

// Pending approval requests: id -> { resolve, timer, data, created }
const pendingRequests = new Map();

// Fire-and-forget notifications (Stop, PostToolUse, etc.)
const notifications = [];
const MAX_NOTIFICATIONS = 100;
const NOTIFICATION_EXPIRY_MS = 300000; // 5 min

// Recent decisions for history display
const recentDecisions = [];
const MAX_HISTORY = 50;

let requestCounter = 0;
let notificationCounter = 0;
let pollerConnected = false;
let lastPollTime = 0;

// ── Sessions ──

// Active sessions: session_id -> { cwd, permission_mode, lastSeen, requestCount }
const activeSessions = new Map();
const SESSION_TIMEOUT_MS = 300000; // 5 min without activity = stale

function trackSession(hookData) {
  const sid = hookData.session_id;
  if (!sid) return;
  const existing = activeSessions.get(sid) || { requestCount: 0 };
  activeSessions.set(sid, {
    cwd: hookData.cwd || existing.cwd || '',
    permission_mode: hookData.permission_mode || existing.permission_mode || '',
    lastSeen: Date.now(),
    requestCount: existing.requestCount + 1
  });
}

// Clean stale sessions periodically
setInterval(() => {
  const now = Date.now();
  for (const [sid, s] of activeSessions) {
    if (now - s.lastSeen > SESSION_TIMEOUT_MS) {
      activeSessions.delete(sid);
    }
  }
}, 30000);

// ── Settings ──

const SETTINGS_PATH = path.join(__dirname, 'crystl-settings.json');

const DEFAULT_SETTINGS = {
  autoApproveMode: 'manual', // 'manual' | 'smart' | 'all'
  paused: false,
  sessionOverrides: {}, // session_id -> 'manual' | 'smart' | 'all'
  enabledNotifications: {
    Stop: true,
    PostToolUse: false,
    SubagentStop: false,
    TaskCompleted: false,
    Notification: true,
    TeammateIdle: false,
    SessionEnd: false
  }
};

// Tools considered safe for read-only operations
const READ_ONLY_TOOLS = ['Read', 'Glob', 'Grep', 'WebSearch', 'WebFetch', 'Agent', 'Explore'];

// Tools auto-approved when Claude Code is in acceptEdits mode
const EDIT_SAFE_TOOLS = [...READ_ONLY_TOOLS, 'Edit', 'Write', 'NotebookEdit'];

function loadSettings() {
  try {
    if (fs.existsSync(SETTINGS_PATH)) {
      return { ...DEFAULT_SETTINGS, ...JSON.parse(fs.readFileSync(SETTINGS_PATH, 'utf8')) };
    }
  } catch (e) {
    log(`Error loading settings: ${e.message}`);
  }
  return { ...DEFAULT_SETTINGS };
}

function saveSettings(settings) {
  fs.writeFileSync(SETTINGS_PATH, JSON.stringify(settings, null, 2));
}

let settings = loadSettings();

function shouldAutoApprove(hookData) {
  if (settings.paused) return false; // kill switch — fall through to all prompts

  // Check per-session override first, then global mode
  const sid = hookData.session_id || '';
  const mode = (sid && settings.sessionOverrides[sid]) || settings.autoApproveMode;

  if (mode === 'manual') return false;
  if (mode === 'all') return true;

  // Smart mode: check permission_mode + tool_name
  const permMode = hookData.permission_mode;
  const toolName = hookData.tool_name || '';

  if (permMode === 'bypassPermissions' || permMode === 'dontAsk') {
    return true;
  }
  if (permMode === 'acceptEdits') {
    return EDIT_SAFE_TOOLS.includes(toolName);
  }
  // plan, default, or unknown — only read-only tools
  return READ_ONLY_TOOLS.includes(toolName);
}

// ── HTTP Server ──

const server = http.createServer((req, res) => {
  // CORS headers — localhost only, no cross-origin
  res.setHeader('Access-Control-Allow-Origin', 'null');
  res.setHeader('Access-Control-Allow-Methods', 'POST, GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  // Validate bearer token on all endpoints
  const authHeader = req.headers['authorization'] || '';
  const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : '';
  if (token !== AUTH_TOKEN) {
    res.writeHead(401, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Unauthorized' }));
    return;
  }

  // Health check
  if (req.method === 'GET' && req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      status: 'ok',
      connected: pollerConnected,
      pending: pendingRequests.size
    }));
    return;
  }

  // Extension polls for pending requests
  if (req.method === 'GET' && req.url === '/pending') {
    lastPollTime = Date.now();
    pollerConnected = true;
    const pending = [];
    for (const [id, req] of pendingRequests) {
      pending.push({
        id,
        tool_name: req.data.tool_name || 'Unknown',
        tool_input: req.data.tool_input || {},
        cwd: req.data.cwd || '',
        session_id: req.data.session_id || '',
        created: req.created
      });
    }
    // Build sessions list
    const sessions = [];
    for (const [sid, s] of activeSessions) {
      sessions.push({
        session_id: sid,
        cwd: s.cwd,
        permission_mode: s.permission_mode,
        lastSeen: s.lastSeen,
        requestCount: s.requestCount,
        override: settings.sessionOverrides[sid] || null
      });
    }

    // Expire old notifications
    const now = Date.now();
    while (notifications.length > 0 && now - notifications[0].created > NOTIFICATION_EXPIRY_MS) {
      notifications.shift();
    }

    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      pending,
      notifications,
      sessions,
      history: recentDecisions.slice(0, MAX_HISTORY),
      settings
    }));
    return;
  }

  // Extension sends a decision
  if (req.method === 'POST' && req.url === '/decide') {
    let body = '';
    req.on('data', chunk => body += chunk);
    req.on('end', () => {
      try {
        const { id, decision } = JSON.parse(body);
        const pending = pendingRequests.get(id);
        if (pending) {
          clearTimeout(pending.timer);
          pendingRequests.delete(id);
          pending.resolve(decision);
          recentDecisions.unshift({
            id,
            tool_name: pending.data.tool_name || 'Unknown',
            tool_input: pending.data.tool_input || {},
            cwd: pending.data.cwd || '',
            session_id: pending.data.session_id || '',
            decision,
            timestamp: Date.now()
          });
          if (recentDecisions.length > MAX_HISTORY) recentDecisions.pop();
          log(`Decision: ${decision} for ${pending.data.tool_name} (${id})`);
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ ok: true }));
        } else {
          res.writeHead(404, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'Request not found or already resolved' }));
        }
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Invalid JSON' }));
      }
    });
    return;
  }

  // Dismiss a notification
  if (req.method === 'POST' && req.url === '/dismiss-notification') {
    let body = '';
    req.on('data', chunk => body += chunk);
    req.on('end', () => {
      try {
        const { id } = JSON.parse(body);
        const idx = notifications.findIndex(n => n.id === id);
        if (idx !== -1) {
          notifications.splice(idx, 1);
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ ok: true }));
        } else {
          res.writeHead(404, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'Notification not found' }));
        }
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Invalid JSON' }));
      }
    });
    return;
  }

  // Get settings
  if (req.method === 'GET' && req.url === '/settings') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(settings));
    return;
  }

  // Update settings
  if (req.method === 'POST' && req.url === '/settings') {
    let body = '';
    req.on('data', chunk => body += chunk);
    req.on('end', () => {
      try {
        const update = JSON.parse(body);
        const validModes = ['manual', 'smart', 'all'];
        let changed = false;

        if (update.autoApproveMode && validModes.includes(update.autoApproveMode)) {
          settings.autoApproveMode = update.autoApproveMode;
          changed = true;
        }
        if (typeof update.paused === 'boolean') {
          settings.paused = update.paused;
          changed = true;
          log(`Bridge ${settings.paused ? 'PAUSED' : 'RESUMED'}`);
        }
        if (update.sessionOverride) {
          const { session_id, mode } = update.sessionOverride;
          if (session_id && (mode === null || validModes.includes(mode))) {
            if (mode === null) {
              delete settings.sessionOverrides[session_id];
              log(`Removed override for session ${session_id.slice(0, 8)}`);
            } else {
              settings.sessionOverrides[session_id] = mode;
              log(`Session ${session_id.slice(0, 8)} override: ${mode}`);
            }
            changed = true;
          }
        }
        if (update.enabledNotifications && typeof update.enabledNotifications === 'object') {
          if (!settings.enabledNotifications) settings.enabledNotifications = { ...DEFAULT_SETTINGS.enabledNotifications };
          Object.assign(settings.enabledNotifications, update.enabledNotifications);
          changed = true;
          log(`Notification settings updated: ${JSON.stringify(settings.enabledNotifications)}`);
        }

        if (changed) {
          saveSettings(settings);
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify(settings));
        } else {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'No valid settings to update' }));
        }
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Invalid JSON' }));
      }
    });
    return;
  }

  // Claude Code hook endpoint — handles all hook types
  // PermissionRequest: hold connection until decision (existing behavior)
  // All others: fire-and-forget, queue as notification for Crystl UI
  if (req.method === 'POST' && req.url.startsWith('/hook')) {
    const urlObj = new URL(req.url, 'http://localhost');
    const hookType = urlObj.searchParams.get('type') || 'PermissionRequest';

    let body = '';
    req.on('data', chunk => body += chunk);
    req.on('end', () => {
      try {
        const hookData = JSON.parse(body);
        trackSession(hookData);

        // ── Non-permission hooks: queue as notification, respond immediately ──
        if (hookType !== 'PermissionRequest') {
          const enabled = settings.enabledNotifications || DEFAULT_SETTINGS.enabledNotifications;
          if (!enabled[hookType]) {
            log(`Notification disabled, ignoring: ${hookType}`);
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({}));
            return;
          }

          const id = 'n' + String(++notificationCounter);
          const notification = {
            id,
            type: hookType,
            session_id: hookData.session_id || '',
            cwd: hookData.cwd || '',
            created: Date.now(),
            // Type-specific fields
            tool_name: hookData.tool_name || null,
            tool_response: hookData.tool_response ? String(hookData.tool_response).slice(0, 200) : null,
            message: hookData.last_assistant_message ? String(hookData.last_assistant_message).slice(0, 200) : (hookData.message || null),
            title: hookData.title || null,
            notification_type: hookData.notification_type || null,
            agent_id: hookData.agent_id || null,
            agent_type: hookData.agent_type || null,
            task_subject: hookData.task_subject || null,
            teammate_name: hookData.teammate_name || null,
            team_name: hookData.team_name || null,
            reason: hookData.reason || null,
            error: hookData.error ? String(hookData.error).slice(0, 200) : null
          };

          notifications.push(notification);
          if (notifications.length > MAX_NOTIFICATIONS) notifications.shift();

          log(`Notification queued: ${hookType} (${id})${hookData.tool_name ? ' tool=' + hookData.tool_name : ''}`);
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({}));
          return;
        }

        // ── PermissionRequest: hold connection until Allow/Deny ──
        const id = String(++requestCounter);
        const toolName = hookData.tool_name || 'Unknown';

        log(`Permission request: ${toolName} (${id}) [mode: ${hookData.permission_mode || '?'}]`);

        // Kill switch — fall through to normal terminal prompt
        if (settings.paused) {
          log(`Paused, falling through: ${toolName} (${id})`);
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({}));
          return;
        }

        // Check auto-approve settings
        if (shouldAutoApprove(hookData)) {
          log(`Auto-approved: ${toolName} (${id}) [${settings.autoApproveMode} mode]`);
          recentDecisions.unshift({
            id, tool_name: toolName,
            tool_input: hookData.tool_input || {},
            cwd: hookData.cwd || '',
            session_id: hookData.session_id || '',
            decision: 'auto-approved', timestamp: Date.now()
          });
          if (recentDecisions.length > MAX_HISTORY) recentDecisions.pop();
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({
            hookSpecificOutput: {
              hookEventName: 'PermissionRequest',
              decision: { behavior: 'allow' }
            }
          }));
          return;
        }

        // If no poller connected recently, fall through to normal prompt
        if (!pollerConnected) {
          log(`No poller connected, falling through`);
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({}));
          return;
        }

        // Create pending request with timeout
        const promise = new Promise((resolve) => {
          const timer = setTimeout(() => {
            pendingRequests.delete(id);
            resolve(null);
            recentDecisions.unshift({
              id, tool_name: toolName,
              tool_input: hookData.tool_input || {},
              cwd: hookData.cwd || '',
              session_id: hookData.session_id || '',
              decision: 'expired', timestamp: Date.now()
            });
            if (recentDecisions.length > MAX_HISTORY) recentDecisions.pop();
            log(`Expired: ${toolName} (${id})`);
          }, TIMEOUT_MS);

          pendingRequests.set(id, {
            resolve, timer,
            data: hookData,
            created: Date.now()
          });
        });

        // Wait for decision then respond to Claude Code
        promise.then((decision) => {
          res.writeHead(200, { 'Content-Type': 'application/json' });
          if (decision === 'allow') {
            res.end(JSON.stringify({
              hookSpecificOutput: {
                hookEventName: 'PermissionRequest',
                decision: { behavior: 'allow' }
              }
            }));
          } else if (decision === 'deny') {
            res.end(JSON.stringify({
              hookSpecificOutput: {
                hookEventName: 'PermissionRequest',
                decision: { behavior: 'deny', message: 'Denied from Crystl' }
              }
            }));
          } else {
            // Timeout — fall through to normal prompt
            res.end(JSON.stringify({}));
          }
        });

      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Invalid JSON' }));
      }
    });
    return;
  }

  res.writeHead(404);
  res.end('Not found');
});

// Mark poller as disconnected if no poll in 10s
setInterval(() => {
  if (Date.now() - lastPollTime > 10000) {
    pollerConnected = false;
  }
}, 5000);

function log(msg) {
  console.log(`[${new Date().toISOString()}] ${msg}`);
}

server.listen(PORT, '127.0.0.1', () => {
  log(`Claude Bridge listening on http://127.0.0.1:${PORT}`);
  log(`Auth token written to ${TOKEN_PATH}`);
  log(`Poll endpoint: GET http://127.0.0.1:${PORT}/pending`);
  log(`Decision endpoint: POST http://127.0.0.1:${PORT}/decide`);
  log(`Hook endpoint: POST http://127.0.0.1:${PORT}/hook`);
});
