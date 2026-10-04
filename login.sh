#!/bin/sh
# Start Info Notch at login:  ./login.sh on   |   ./login.sh off
set -e
cd "$(dirname "$0")"
LABEL=com.infonotch.agent
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
BIN="$HOME/.local/bin/infonotch"
DOMAIN="gui/$(id -u)"

case "$1" in
  on)
    [ -x ./infonotch ] || ./build.sh
    mkdir -p "$HOME/.local/bin" "$HOME/Library/LaunchAgents"
    cp ./infonotch "$BIN"      # copied so moving/deleting this folder won't break login start
    cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$BIN</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
</dict></plist>
PL
    pkill -x infonotch 2>/dev/null || true
    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
    launchctl bootstrap "$DOMAIN" "$PLIST"
    echo "On: Info Notch starts at login (and is running now)."
    ;;
  off)
    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
    rm -f "$PLIST" "$BIN"
    echo "Off: removed login item."
    ;;
  *) echo "usage: ./login.sh on|off"; exit 1 ;;
esac
