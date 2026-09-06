#!/usr/bin/env bash
# Builds, wraps the binary in an .app bundle and registers a LaunchAgent so the
# bar comes back at login.
set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID="dev.claude-usage-bar.menubar"
APP="$HOME/Applications/Claude Usage Bar.app"
PLIST="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
EXEC="ClaudeUsageBar"   # must match CFBundleExecutable

echo "==> building"
swift build -c release

echo "==> installing $APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/$EXEC" "$APP/Contents/MacOS/$EXEC"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Ad-hoc signature: enough for a local bundle, and macOS refuses to keep an
# unsigned menu bar agent running across logins.
codesign --force --sign - "$APP" >/dev/null

echo "==> registering LaunchAgent"
cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>            <string>$BUNDLE_ID</string>
  <key>ProgramArguments</key>
  <array>
    <string>$APP/Contents/MacOS/$EXEC</string>
  </array>
  <key>RunAtLoad</key>        <true/>
  <key>KeepAlive</key>        <false/>
  <key>ProcessType</key>      <string>Interactive</string>
</dict>
</plist>
PLIST_EOF

launchctl bootout "gui/$(id -u)/$BUNDLE_ID" 2>/dev/null || true
pkill -f "$APP/Contents/MacOS/$EXEC" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

sleep 1
if pgrep -f "$APP/Contents/MacOS/$EXEC" >/dev/null; then
  echo "==> running. look at the right-hand side of your menu bar."
else
  echo "==> it did not start; check: launchctl print gui/$(id -u)/$BUNDLE_ID" >&2
  exit 1
fi
