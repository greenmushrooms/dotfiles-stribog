#!/usr/bin/env bash
# Surface Pro 7 cameras (Intel IPU4P): front, rear and IR, via the out-of-tree
# driver github.com/paicheck/surfacepro7-camera-ir @ 92bfe68 plus our patches:
#   0001  dkms.conf: tell DKMS where the IPU4 modules are built
#   0002  IR camera: data-lane timing 1269 on CSI-2 index 1, 100 us CPU latency
#   0003  IR emitter: ov7251 strobe_pattern option (Windows' 0x3b81 pattern)
# The IR fixes come from surface-kit / linux-surface discussion #1353.
#
#   sudo bash install-camera.sh
#
# Needs a reboot afterwards (the running camera stack can't be swapped live).
# The firmware (ipu4p_cpd.bin) is fetched once by the upstream
# scripts/fetch-firmware.sh; this script runs it if it's missing.
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "run me with sudo" >&2; exit 1; }

HERE=$(cd "$(dirname "$0")" && pwd)
NAME=surfacepro7-camera-ir
VER=1
COMMIT=92bfe68
DST=/usr/src/$NAME-$VER

pacman -S --needed --noconfirm dkms msitools git

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
git clone -q https://github.com/paicheck/surfacepro7-camera-ir "$tmp/src"
git -C "$tmp/src" checkout -q "$COMMIT"
for p in "$HERE"/patches/*.patch; do
	echo "applying $(basename "$p")"
	patch -d "$tmp/src" -p1 -s < "$p"
done
rm -rf "$tmp/src/.git"

[ -d "$DST" ] && { rm -rf "$DST.prev"; mv "$DST" "$DST.prev"; }
cp -a "$tmp/src" "$DST"
chown -R root:root "$DST"

dkms remove -m "$NAME" -v "$VER" --all >/dev/null 2>&1 || true
dkms add -m "$NAME" -v "$VER"
dkms install -m "$NAME" -v "$VER" -k "$(uname -r)"

# IR emitter on (only while the IR camera streams).
install -D -m 644 /dev/stdin /etc/modprobe.d/surface-camera.conf <<'EOF'
# Surface Pro 7 IR emitter, driven by the OV7251 strobe; see dotfiles surface-camera/
options ov7251 strobe_pattern=255
EOF

[ -s /lib/firmware/ipu4p_cpd.bin ] || bash "$DST/scripts/fetch-firmware.sh"

echo "==> done; reboot to load the new camera stack"
