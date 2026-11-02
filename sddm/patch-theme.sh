#!/usr/bin/env bash
# Patch sddm-astronaut-theme's virtual keyboard (Main.qml):
#  - open on start when VirtualKeyboardAutoShow="true" (written by surface-xsetup)
#  - full width in portrait: KeyboardSizePortrait (default 1.0), KeyboardSize
#    stays the landscape width
# Idempotent; re-run after updating the theme.
#
#   patch-theme.sh [theme-dir]
set -euo pipefail

MAIN=${1:-/usr/share/sddm/themes/sddm-astronaut-theme}/Main.qml

if grep -q VirtualKeyboardAutoShow "$MAIN"; then
  echo "auto-show: already patched"
else
  # Delay a little so the password field has focus before the keyboard opens.
  sed -i '/function switchState() {/a\
            // dotfiles/sddm: open at start when no hardware keyboard is present.\
            onLoaded: if (config.VirtualKeyboardAutoShow == "true") autoShowTimer.start()\
            Timer { id: autoShowTimer; interval: 400; onTriggered: virtualKeyboard.state = "visible" }' "$MAIN"
  grep -q VirtualKeyboardAutoShow "$MAIN" || { echo "auto-show patch failed: switchState() not found" >&2; exit 1; }
  echo "auto-show: patched"
fi

if grep -q KeyboardSizePortrait "$MAIN"; then
  echo "portrait width: already patched"
else
  sed -i 's|^\( *\)width: config.KeyboardSize == "" ? parent.width \* 0.4 : parent.width \* config.KeyboardSize$|\1// dotfiles/sddm: separate width in portrait (follows rotation).\
\1width: parent.width * (parent.height > parent.width\
\1    ? (config.KeyboardSizePortrait == "" ? 1.0 : config.KeyboardSizePortrait)\
\1    : (config.KeyboardSize == "" ? 0.4 : config.KeyboardSize))|' "$MAIN"
  grep -q KeyboardSizePortrait "$MAIN" || { echo "portrait patch failed: width line not found" >&2; exit 1; }
  echo "portrait width: patched"
fi
