#!/usr/bin/env bash
# Face unlock (Howdy) with the Surface Pro 7 IR camera, for sudo and hyprlock.
# Needs the camera stack from surface-camera/ (IR timing fix + emitter).
#
#   sudo bash install-face.sh            install/update Howdy + config
#   sudo bash install-face.sh pam        also enable face unlock for sudo/hyprlock
#   sudo bash install-face.sh nopam      remove it from sudo/hyprlock again
#
# The SDDM login is deliberately left alone: KWallet unlocks from the login
# password, which a face login doesn't provide.
#
# python-dlib comes from the AUR (built with CUDA off); this script installs
# the package found in ~/.cache/howdy-build/python-dlib if it isn't installed.
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "run me with sudo" >&2; exit 1; }
: "${SUDO_USER:?run me through sudo from your account}"

HERE=$(cd "$(dirname "$0")" && pwd)
CONFIG=/etc/howdy/config.ini
PAM_LINE="auth sufficient pam_howdy.so"
PAM_FILES=(/etc/pam.d/sudo /etc/pam.d/hyprlock)

pam_on() {
	for f in "${PAM_FILES[@]}"; do
		grep -q 'pam_howdy.so' "$f" && continue
		cp -n "$f" "$f.pre-howdy"
		# First auth line: face first, password as the fallback.
		sed -i "0,/^auth/s//$PAM_LINE\n&/" "$f"
		echo "face unlock enabled in $f"
	done
}

pam_off() {
	for f in "${PAM_FILES[@]}"; do
		sed -i '/pam_howdy.so/d' "$f" && echo "face unlock removed from $f"
	done
}

case "${1:-install}" in
	pam)   pam_on; exit 0 ;;
	nopam) pam_off; exit 0 ;;
	install) ;;
	*) echo "usage: install-face.sh [install|pam|nopam]" >&2; exit 2 ;;
esac

pacman -S --needed --noconfirm python-opencv python-numpy v4l-utils libinih libevdev meson ninja cmake git

if ! pacman -Q python-dlib >/dev/null 2>&1; then
	pkg=$(ls -t "/home/$SUDO_USER/.cache/howdy-build/python-dlib"/python-dlib-[0-9]*.pkg.tar.zst 2>/dev/null | head -1)
	[ -n "$pkg" ] || { echo "build python-dlib first (makepkg in ~/.cache/howdy-build/python-dlib)" >&2; exit 1; }
	pacman -U --noconfirm "$pkg"
fi

# Build the patched Howdy as the user, install as root.
build=/home/$SUDO_USER/.cache/howdy-build/howdy-surface
sudo -u "$SUDO_USER" bash -c "rm -rf '$build' && mkdir -p '$build' && cp '$HERE'/{PKGBUILD,howdy.install,polkit-agent-helper-howdy.conf,howdy-surface-ir.patch,surface_ir_reader.py} '$build'/ && cd '$build' && makepkg -f --noconfirm"
pacman -U --noconfirm "$(ls -t "$build"/howdy-surface-git-*.pkg.tar.zst | grep -v debug | head -1)"

set_option() { sed -i "s|^$1 = .*|$1 = $2|" "$CONFIG"; }
set_option device_path /dev/media0
set_option recording_plugin surface_ir
# The room behind the face is mostly dark under the emitter alone
set_option dark_threshold 90
chmod 644 "$CONFIG"
install -d -m 700 /etc/howdy/models

echo
echo "Installed. Next:"
echo "  sudo howdy add                      # enrol your face (look at the camera)"
echo "  sudo howdy test                     # optional: live view"
echo "  sudo bash $HERE/install-face.sh pam # turn it on for sudo + hyprlock"
