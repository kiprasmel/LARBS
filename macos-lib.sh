# Shared helpers for the macos*.sh scripts. Sourced, not run.

# Sets a keyboard shortcut (system settings > keyboard > keyboard shortcuts).
hotkey() { # <symbolichotkey id> <enabled: true|false> <keycode> <modifier mask>
	defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add "$1" \
		"<dict><key>enabled</key><$2/><key>value</key><dict><key>parameters</key><array><integer>65535</integer><integer>$3</integer><integer>$4</integer></array><key>type</key><string>standard</string></dict></dict>"
}

# Applies changed shortcuts w/o log-out.
applyhotkeys() {
	/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
}

# Mission control: "switch to desktop N".
# desktop 1-10 = ctrl+1..0, desktop 11-16 = alt+1..6 (macos maxes out at 16).
# numbering spans displays (1-10 on 1st, 11-20 on 2nd); only works for desktops that exist.
desktophotkeys() { # <enabled: true|false>
	ctrl=262144 alt=524288
	n=0
	for key in 18 19 20 21 23 22 26 28 25 29; do # keycodes for 1..9,0
		hotkey $((118 + n)) "$1" $key $ctrl
		[ $n -lt 6 ] && hotkey $((128 + n)) "$1" $key $alt
		n=$((n + 1))
	done
	applyhotkeys
}

# skhd loads its space bindings from ~/.config/yabai/skhdrc-spaces (see skhdrc there),
# a symlink to skhdrc-spaces-yabai or skhdrc-spaces-native.
skhdspaces() { # <yabai|native>
	ln -sfn "skhdrc-spaces-$1" "$HOME/.config/yabai/skhdrc-spaces"
	skhd --reload 2>/dev/null # not running yet on a fresh install, then it loads the config on start
}

# yabai's scripting addition (needed to focus spaces) requires filesystem protections & debugging restrictions off.
sipallowsyabai() {
	csrutil status | grep -qE "status: disabled|Filesystem Protections: disabled" &&
		! csrutil status | grep -q "Debugging Restrictions: enabled"
}
