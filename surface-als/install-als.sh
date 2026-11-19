#!/usr/bin/env bash
# Surface Pro 7 ambient light sensor (MSHW0184) = AMS TCS3430, not the APDS9960
# Linux binds to it. Installs the TCS3430 driver (Paul Kocialkowski's unmerged
# IIO driver + Surface fixes, see driver/tcs3430-surface.patch) via DKMS and
# keeps apds9960 off the sensor.
#
#   sudo bash install-als.sh
#
# Undo: dkms remove tcs3430-surface/1 --all; rm the two files under /etc below.
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "run me with sudo" >&2; exit 1; }

SRC_DIR=$(cd "$(dirname "$0")" && pwd)
NAME=tcs3430-surface
VER=1

pacman -S --needed --noconfirm dkms

rm -rf "/usr/src/$NAME-$VER"
install -d "/usr/src/$NAME-$VER"
install -m 644 "$SRC_DIR"/driver/{tcs3430.c,Kbuild,dkms.conf} "/usr/src/$NAME-$VER/"
dkms remove -m "$NAME" -v "$VER" --all >/dev/null 2>&1 || true
dkms add -m "$NAME" -v "$VER"
dkms install -m "$NAME" -v "$VER" -k "$(uname -r)"

# apds9960 would grab MSHW0184 first (and can't drive this chip).
install -D -m 644 /dev/stdin /etc/modprobe.d/surface-als.conf <<'EOF'
# Surface MSHW0184 is an AMS TCS3430; see dotfiles surface-als/
blacklist apds9960
EOF

# 64x gain: at the default 4x a lit room reads single digits.
install -D -m 644 /dev/stdin /etc/udev/rules.d/90-surface-als.rules <<'EOF'
ACTION=="add", SUBSYSTEM=="iio", ATTR{name}=="tcs3430", ATTR{in_intensity_hardwaregain}="64"
EOF
udevadm control --reload

# Switch over now, without a reboot.
modprobe -r apds9960 2>/dev/null || true
modprobe -r tcs3430 2>/dev/null || true
modprobe tcs3430
udevadm trigger --subsystem-match=iio --action=add
sleep 1

for d in /sys/bus/iio/devices/iio:device*; do
	[ "$(cat "$d/name")" = tcs3430 ] || continue
	echo "sensor: $d  gain=$(cat "$d/in_intensity_hardwaregain")  Y=$(cat "$d/in_intensity_y_raw")"
done
modinfo -n tcs3430
