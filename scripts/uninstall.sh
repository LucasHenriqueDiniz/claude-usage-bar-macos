#!/usr/bin/env bash
# Removes the agent and the bundle. Preferences are left alone; see the README
# for how to drop those too.
set -euo pipefail

BUNDLE_ID="dev.claude-usage-bar.menubar"
APP="$HOME/Applications/Claude Usage Bar.app"
PLIST="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"

launchctl bootout "gui/$(id -u)/$BUNDLE_ID" 2>/dev/null || true
pkill -f "$APP/Contents/MacOS/ClaudeUsageBar" 2>/dev/null || true
rm -f "$PLIST"
rm -rf "$APP"
echo "removed. preferences kept: defaults delete $BUNDLE_ID"
