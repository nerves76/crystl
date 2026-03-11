#!/usr/bin/env node
// Claude Code <-> Snackbar Bridge Server
// Receives PermissionRequest hooks from Claude Code via HTTP
// Snackbar extension polls for pending requests and sends decisions via HTTP

const http = require('http');

const PORT = parseInt(process.env.CLAUDE_BRIDGE_PORT || '19280', 10);
const TIMEOUT_MS = 60000; // 60s before falling through to normal prompt

// Pending approval requests: id -> { resolve, timer, data, created }
const pendingRequests = new Map();

// Recent decisions for history display
const recentDecisions = [];
const MAX_HISTORY = 50;

let requestCounter = 0;
let pollerConnected = false;
let lastPollTime = 0;

// ── HTTP Server ──

const server = http.createServer((req, res) => {
  // CORS headers for extension
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
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
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ pending, history: recentDecisions.slice(0, 20) }));
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

  // Claude Code PermissionRequest hook endpoint
  if (req.method === 'POST' && req.url === '/hook') {
    let body = '';
    req.on('data', chunk => body += chunk);
    req.on('end', () => {
      try {
        const hookData = JSON.parse(body);
        const id = String(++requestCounter);
        const toolName = hookData.tool_name || 'Unknown';

        log(`Permission request: ${toolName} (${id})`);
        log(`Hook payload: ${JSON.stringify(hookData).slice(0, 500)}`);

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
                decision: { behavior: 'deny', message: 'Denied from Snackbar' }
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
  log(`Poll endpoint: GET http://127.0.0.1:${PORT}/pending`);
  log(`Decision endpoint: POST http://127.0.0.1:${PORT}/decide`);
  log(`Hook endpoint: POST http://127.0.0.1:${PORT}/hook`);
});
