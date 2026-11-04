#!/bin/sh

# Spaces when SIP is enabled (e.g. a managed work laptop):
# yabai can't focus spaces w/o its scripting addition, so switch desktops w/ macos' native shortcuts,
# and drop skhd's yabai space bindings so they don't swallow the keys.
# Switch to yabai w/ ./macos-spaces-yabai-no-sip.sh

. "$(dirname "$0")/macos-lib.sh"

skhdspaces native
desktophotkeys true

echo "spaces: native. ctrl+1..0 = desktop 1-10, alt+1..6 = desktop 11-16"
