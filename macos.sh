#!/bin/sh

# LARBS for macOS: homebrew, dotfiles and system settings.
# Run via larbs.sh, or directly from the LARBS repo. Safe to re-run.
# [ ] check webarchive for my notes for the mac setup

### OPTIONS AND VARIABLES ###

while getopts ":r:s:h" o; do case "${o}" in
	h) printf "Optional arguments for custom use:\\n  -r: Dotfiles repository (url)\\n  -s: Spaces: native (SIP enabled) or yabai (SIP disabled). Default: detected from SIP\\n  -h: Show this message\\n" && exit ;;
	r) dotfilesrepo=${OPTARG} ;;
	s) spaces=${OPTARG} ;;
	*) printf "Invalid option: -%s\\n" "$OPTARG" && exit 1 ;;
esac done

[ -z "$dotfilesrepo" ] && dotfilesrepo="https://github.com/kiprasmel/voidrice.git"

larbsdir="$(cd "$(dirname "$0")" && pwd)"
. "$larbsdir/macos-lib.sh"

### FUNCTIONS ###

error() {
	# Log to stderr and exit with failure.
	printf "%s\n" "$1" >&2
	exit 1
}

dotfiles() {
	# Same as the `config` alias from the dotfiles' zshrc.
	# -C: `submodule` refuses to run from outside the work tree.
	git -C "$HOME" --git-dir="$HOME/.dotfiles" --work-tree="$HOME" "$@"
}

installbrew() {
	command -v brew >/dev/null 2>&1 && return
	/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || return 1
	eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"
}

installdotfiles() {
	# A regular clone w/ .git moved to ~/.dotfiles, so origin/* remote-tracking branches work (unlike a bare clone).
	# Only on first run, since checking out into ~ overwrites conflicting files.
	if [ ! -d "$HOME/.dotfiles" ]; then
		tmp="$(mktemp -d)"
		git clone "$dotfilesrepo" "$tmp/dotfiles" || return 1
		mv "$tmp/dotfiles/.git" "$HOME/.dotfiles"
		rm -rf "$tmp"
		dotfiles reset --hard || return 1
	fi
	dotfiles submodule update --init --recursive
}

setupiterm() {
	# Load settings from the dotfiles submodule, ~/.config/iterm
	# - NOT ~/.config/iterm2: that's iterm's own runtime dir (AppSupport symlink, sockets),
	#   and the submodule's core.worktree points at ~/.config/iterm, so git never sees files put in iterm2
	# - iterm must be quit while switching (see itermprefs). when running inside it, quitting it ends
	#   this script too, so this runs last, asks first, and leaves the rest to a detached helper.
	# verify: `git -C ~/.config/iterm status` stays clean
	# hotkey windows: opt+u = scratchpad, opt+a = calc.
	# karabiner swaps cmd<->opt on non-apple keyboards, not the built-in one
	[ "$(defaults read com.googlecode.iterm2 PrefsCustomFolder 2>/dev/null)" = "$HOME/.config/iterm" ] &&
		[ "$(defaults read com.googlecode.iterm2 LoadPrefsFromCustomFolder 2>/dev/null)" = 1 ] && return
	if ! pgrep -x -u "$(id -u)" iTerm2 >/dev/null; then
		itermprefs
	# the env vars alone aren't enough: they're also set e.g. over ssh, or sudo from iterm
	elif [ "$TERM_PROGRAM" = iTerm.app ] || [ "$LC_TERMINAL" = iTerm2 ]; then
		answer=
		(: </dev/tty) 2>/dev/null && printf "\nQuit iTerm now, to load its settings from the dotfiles? This window closes too, so read the above first. [y/N] " >/dev/tty &&
			read -r answer </dev/tty
		# shellcheck disable=SC2016 # $1 is for the inner sh
		case "$answer" in
		[yY]*) nohup sh -c '. "$1/macos-lib.sh" && quitiTermthenprefs' _ "$larbsdir" >/dev/null 2>&1 & ;;
		*) echo "Skipped the iTerm settings. Re-run from Terminal.app to apply them." ;;
		esac
	else
		quitiTermthenprefs || echo "iTerm didn't quit, skipped its settings. Re-run to apply them." >&2
	fi
}

setupssh() {
	ls "$HOME"/.ssh/id_* >/dev/null 2>&1 && return
	ssh-keygen -t rsa -b 4096 -C "$(git config --global user.email)"
}

systemsettings() {
	# dock: disable rearrange spaces by recent use (v annoying)
	defaults write com.apple.dock mru-spaces -bool false
	killall Dock 2>/dev/null # not running when not logged in at the screen

	# desktop & dock: click wallpaper to reveal desktop -> only in stage manager
	defaults write com.apple.WindowManager EnableStandardClickToShowDesktop -bool false
	# desktop & dock: no margins around tiled windows
	defaults write com.apple.WindowManager EnableTiledWindowMargins -bool false

	# keyboard shortcuts, to leave ctrl + arrows to tmux (ctrl+up/down: previous/next window,
	# ctrl/opt+left/right: move the window to an earlier/later number):
	#  - mission control / application windows: ctrl + up/down arr -> opt + up/down arr;
	#  - move left/right a space: disabled, so opt + left/right reach tmux too.
	#    spaces are switched w/ ctrl/opt+N instead (macos-spaces-*.sh).
	opt=$((mod_fn + mod_opt)) shiftopt=$((mod_fn + mod_opt + mod_shift))
	hotkey $hk_missioncontrol true $key_up $opt; hotkey $hk_missioncontrol_shift true $key_up $shiftopt
	hotkey $hk_appwindows true $key_down $opt; hotkey $hk_appwindows_shift true $key_down $shiftopt
	hotkey $hk_spaceleft false $key_left $opt; hotkey $hk_spaceleft_shift false $key_left $shiftopt
	hotkey $hk_spaceright false $key_right $opt; hotkey $hk_spaceright_shift false $key_right $shiftopt
	applyhotkeys

	# optional: crossfade instead of slide when switching desktops (not really shorter, just feels snappier).
	# also affects other system animations. writing this domain may need full disk access for the terminal,
	# otherwise: system settings > accessibility > display > reduce motion
	#defaults write com.apple.universalaccess reduceMotion -bool true

	# key repeat rate. needs log-out & re-login to apply
	# https://mac-key-repeat.zaymon.dev/
	defaults write -g InitialKeyRepeat -int 10
	defaults write -g KeyRepeat -int 2
	defaults write -g ApplePressAndHoldEnabled -bool false

	# ctrl+cmd+drag anywhere in a window to move it
	defaults write -g NSWindowShouldDragOnGesture -bool true
}

setupspaces() {
	# Spaces: yabai if SIP allows its scripting addition, otherwise native macos shortcuts.
	# Switch later by running either script directly.
	if [ -z "$spaces" ]; then
		sipallowsyabai && spaces=yabai || spaces=native
	fi
	case "$spaces" in
	native) sh "$larbsdir/macos-spaces-native.sh" ;;
	yabai) sh "$larbsdir/macos-spaces-yabai-no-sip.sh" ;;
	*) echo "Invalid spaces mode \`$spaces\` (native or yabai), skipping." >&2 ;;
	esac
}

startservices() {
	pgrep -x -u "$(id -u)" yabai >/dev/null || yabai --start-service
	pgrep -x -u "$(id -u)" skhd >/dev/null || skhd --start-service
}

finalize() {
	echo "
All done! Still manual:
- Log out and back in (key repeat).
- Allow yabai and skhd in system settings > privacy & security > accessibility.
- Add the ssh key to github (\`gh auth login\`), and into ~/.ssh/config for Host github.com.
- Switch the dotfiles remote to ssh: config remote set-url origin $(echo "$dotfilesrepo" | sed -E 's|^https://([^/]+)/|git@\1:|')
- ~/forkprojects/xbar-plugins/ -> Weather/sunrise-sunset/ ln -s, System/disable-sleep/install.sh
- Remove unneeded deps that create login items: adobe, alpine, macfuse, mbsync, redis-server
- Spaces mode is \`$spaces\`. Switch w/ $larbsdir/macos-spaces-native.sh or macos-spaces-yabai-no-sip.sh
- Resolve any conflicts vscode.sh listed above. Re-run $larbsdir/vscode.sh to sync w/ the gist later."
}

### THE ACTUAL SCRIPT ###

[ "$(uname -s)" = Darwin ] || error "macos.sh is for macOS. Use larbs.sh, which picks the right script."

installbrew || error "Failed to install homebrew."

brew bundle install --file="$larbsdir/Brewfile" ||
	echo "Some Brewfile entries failed to install, see above. Continuing." >&2

installdotfiles || error "Failed to install the dotfiles."

# vscodium/cursor/vscode settings, keybindings & extensions from the gist. Asks about local changes.
sh "$larbsdir/vscode.sh"

setupssh

systemsettings

setupspaces

startservices

finalize

# Last, since it may quit the iterm this runs in.
setupiterm
