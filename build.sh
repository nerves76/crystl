#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="$HOME/Applications"
BRIDGE_LABEL="com.apprvr.claude-bridge"
BRIDGE_PLIST="$HOME/Library/LaunchAgents/$BRIDGE_LABEL.plist"

echo "==> Building Apprvr..."

# Compile Swift menu bar app
swiftc -O -o "$SCRIPT_DIR/Apprvr" \
  -framework Cocoa \
  "$SCRIPT_DIR/Apprvr.swift"

echo "==> Installing to $INSTALL_DIR..."

mkdir -p "$INSTALL_DIR"

# Create minimal .app bundle for Apprvr
APP_DIR="$INSTALL_DIR/Apprvr.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$SCRIPT_DIR/Apprvr" "$APP_DIR/Contents/MacOS/Apprvr"

# Info.plist for the app
cat > "$APP_DIR/Contents/Info.plist" << 'PLISTEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.apprvr.app</string>
    <key>CFBundleName</key>
    <string>Apprvr</string>
    <key>CFBundleExecutable</key>
    <string>Apprvr</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
</dict>
</plist>
PLISTEOF

echo "==> Apprvr.app installed to $APP_DIR"

# ── Claude Bridge ──

NODE_PATH="$(which node 2>/dev/null || true)"

if [ -z "$NODE_PATH" ]; then
  echo ""
  echo "==> Skipping Claude Bridge (Node.js not found)"
  echo "    Install Node.js to enable the bridge server"
  echo "    Then re-run this script"
  exit 0
fi

BRIDGE_DEST="$INSTALL_DIR/claude-bridge.js"

echo "==> Installing Claude Bridge..."

cp "$SCRIPT_DIR/claude-bridge.js" "$BRIDGE_DEST"

# Unload existing agent if running
launchctl unload "$BRIDGE_PLIST" 2>/dev/null || true

# Generate LaunchAgent plist
cat > "$BRIDGE_PLIST" << LAEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$BRIDGE_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$NODE_PATH</string>
        <string>$BRIDGE_DEST</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/claude-bridge.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/claude-bridge.log</string>
</dict>
</plist>
LAEOF

launchctl load "$BRIDGE_PLIST"

echo "==> Claude Bridge running on port 19280"
echo ""
echo "==> Done! To start Apprvr:"
echo "    open $APP_DIR"
echo ""
echo "Add to ~/.claude/settings.json:"
echo '  "hooks": {'
echo '    "PermissionRequest": [{'
echo '      "matcher": "*",'
echo '      "hooks": [{ "type": "http", "url": "http://127.0.0.1:19280/hook" }]'
echo '    }]'
echo '  }'
