# Shared helpers for the macos*.sh scripts. Sourced, not run.

# Keyboard shortcut ids (com.apple.symbolichotkeys).
# The _shift ones are the slow-motion twins (same shortcut + shift), which system settings changes alongside.
hk_missioncontrol=32 hk_missioncontrol_shift=34
hk_appwindows=33 hk_appwindows_shift=35
hk_spaceleft=79 hk_spaceleft_shift=80
hk_spaceright=81 hk_spaceright_shift=82
hk_desktop1=118 # "switch to desktop N" is hk_desktop1 + N - 1, up to desktop 16

# Keycodes.
key_1=18 key_2=19 key_3=20 key_4=21 key_5=23 key_6=22 key_7=26 key_8=28 key_9=25 key_0=29
key_left=123 key_right=124 key_down=125 key_up=126

# Modifier masks. Add them up to combine. Arrow keys always carry mod_fn.
mod_shift=131072 mod_ctrl=262144 mod_opt=524288 mod_fn=8388608

# Sets a keyboard shortcut (system settings > keyboard > keyboard shortcuts).
hotkey() { # <symbolichotkey id> <enabled: true|false> <keycode> <modifier mask>
	defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add "$1" \
		"<dict><key>enabled</key><$2/><key>value</key><dict><key>parameters</key><array><integer>65535</integer><integer>$3</integer><integer>$4</integer></array><key>type</key><string>standard</string></dict></dict>"
}

# Applies changed shortcuts w/o log-out.
# Only for the user logged in at the screen: it applies them to that session, so for another user
# (e.g. via sudo) it'd override the logged in user's shortcuts. Others get them at their next login.
applyhotkeys() {
	[ "$(/usr/bin/stat -f %Su /dev/console)" = "$(id -un)" ] || return 0
	/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
}

# Mission control: "switch to desktop N".
# desktop 1-10 = ctrl+1..0, desktop 11-16 = alt+1..6 (macos maxes out at 16).
# numbering spans displays (1-10 on 1st, 11-20 on 2nd); only works for desktops that exist.
desktophotkeys() { # <enabled: true|false>
	n=0
	for key in $key_1 $key_2 $key_3 $key_4 $key_5 $key_6 $key_7 $key_8 $key_9 $key_0; do
		hotkey $((hk_desktop1 + n)) "$1" "$key" $mod_ctrl
		[ $n -lt 6 ] && hotkey $((hk_desktop1 + 10 + n)) "$1" "$key" $mod_opt
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
