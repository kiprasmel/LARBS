#!/bin/sh

# Spaces when SIP is (partially) disabled:
# yabai focuses spaces via its scripting addition, so use skhd's yabai space bindings,
# and turn off macos' native desktop shortcuts.
# https://github.com/koekeishiya/yabai/wiki/Disabling-System-Integrity-Protection
# Switch back w/ ./macos-spaces-native.sh

. "$(dirname "$0")/macos-lib.sh"

sipallowsyabai || {
	echo "SIP is enabled, so yabai can't load its scripting addition. To disable it:
1. Boot into recovery (apple silicon: hold the power button), open Terminal, and run:
	csrutil enable --without fs --without debug --without nvram
2. Reboot and re-run this script.
Or stay w/ native spaces: ./macos-spaces-native.sh" >&2
	exit 1
}

# Apple silicon: allow the scripting addition's arm64e code. Needs a reboot.
if [ "$(uname -m)" = arm64 ] && ! nvram boot-args 2>/dev/null | grep -q -- -arm64e_preview_abi; then
	sudo nvram boot-args=-arm64e_preview_abi || exit 1
	echo "Set boot-args. Reboot and re-run this script." >&2
	exit 1
fi

# Let yabairc load the scripting addition w/o a password.
# The hash pins the binary, so re-run this after upgrading yabai.
yabai="$(command -v yabai)"
sudoers="$(mktemp)"
printf '"%s" ALL=(root) NOPASSWD: sha256:%s %s --load-sa\n' \
	"$(whoami)" "$(shasum -a 256 "$yabai" | cut -d ' ' -f 1)" "$yabai" >"$sudoers"
if ! visudo -cf "$sudoers" >/dev/null || ! sudo install -m 0440 "$sudoers" /private/etc/sudoers.d/yabai; then
	rm -f "$sudoers"
	echo "Failed to install the yabai sudoers entry." >&2
	exit 1
fi
rm -f "$sudoers"
sudo yabai --load-sa

skhdspaces yabai
desktophotkeys false

echo "spaces: yabai. ctrl+1..0 = space 1-10, alt+1..0 = 11-20, ctrl+alt+1..0 = 21-30, cmd+tab = recent"
