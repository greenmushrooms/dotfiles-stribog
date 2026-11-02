#!/usr/bin/env bash
# Surface login screen: auto-rotate and on-screen keyboard in SDDM.
#
#   sudo bash install-sddm.sh
#
# Takes effect at the next boot / logout (restarting sddm kills your session).
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "run me with sudo" >&2; exit 1; }

SRC_DIR=$(cd "$(dirname "$0")" && pwd)

# xrandr/xinput: rotate the greeter's X server; qt6-virtualkeyboard: the OSK.
pacman -S --needed --noconfirm xorg-xrandr xorg-xinput qt6-virtualkeyboard iio-sensor-proxy

install -D -m 755 -o root -g root "$SRC_DIR/surface-xsetup"  /usr/local/lib/sddm/surface-xsetup
install -D -m 644 -o root -g root "$SRC_DIR/20-surface.conf" /etc/sddm.conf.d/20-surface.conf
echo "installed /usr/local/lib/sddm/surface-xsetup and /etc/sddm.conf.d/20-surface.conf"

bash "$SRC_DIR/patch-theme.sh"
