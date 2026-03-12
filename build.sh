#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="$HOME/Applications"
BRIDGE_LABEL="com.crystl.claude-bridge"
BRIDGE_PLIST="$HOME/Library/LaunchAgents/$BRIDGE_LABEL.plist"

echo "==> Building Crystl (Swift Package)..."

cd "$SCRIPT_DIR"
swift build -c release 2>&1

BUILT_BIN="$(swift build -c release --show-bin-path)/Crystl"

echo "==> Installing to $INSTALL_DIR..."

mkdir -p "$INSTALL_DIR"

# Create .app bundle
APP_DIR="$INSTALL_DIR/Crystl.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BUILT_BIN" "$APP_DIR/Contents/MacOS/Crystl"

# Copy logo assets into Resources
if [ -d "$SCRIPT_DIR/logo" ]; then
    cp "$SCRIPT_DIR"/logo/*.png "$APP_DIR/Contents/Resources/" 2>/dev/null || true
    cp "$SCRIPT_DIR"/logo/*.icns "$APP_DIR/Contents/Resources/" 2>/dev/null || true
fi

# Info.plist — regular app (shows in dock)
cat > "$APP_DIR/Contents/Info.plist" << 'PLISTEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.crystl.app</string>
    <key>CFBundleName</key>
    <string>Crystl</string>
    <key>CFBundleExecutable</key>
    <string>Crystl</string>
    <key>CFBundleVersion</key>
    <string>2.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
</dict>
</plist>
PLISTEOF

echo "==> Crystl.app installed to $APP_DIR"

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

# Unload existing agent if running (try both old and new labels)
launchctl unload "$BRIDGE_PLIST" 2>/dev/null || true
launchctl unload "$HOME/Library/LaunchAgents/com.apprvr.claude-bridge.plist" 2>/dev/null || true

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
echo "==> Done! To start Crystl:"
echo "    open $APP_DIR"
