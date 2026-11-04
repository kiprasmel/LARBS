#!/bin/sh

# Runs LARBS (this working tree, uncommitted changes included) as a throwaway macOS user,
# then checks the result. Run it twice to test both a fresh install and a re-run.
#
# One-time setup, as an admin: a non-admin user, and passwordless sudo for you to run things *as it*:
#   sudo sysadminctl -addUser larbstest -fullName "LARBS test" -password larbstest
#   echo "#$(id -u) ALL=(larbstest) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/larbstest
# Undo:
#   sudo sysadminctl -deleteUser larbstest && sudo rm /etc/sudoers.d/larbstest
#
# The user isn't logged in at the screen, so the shortcuts apply at its next login,
# and starting yabai/skhd fails. Neither is checked.

user="${1:-larbstest}"
repo="${2:-https://github.com/kiprasmel/voidrice}"
larbsdir="$(cd "$(dirname "$0")/.." && pwd)"
copy="/Users/Shared/larbs-test"

as() { (cd / && sudo -n -u "$user" -H "$@"); }
as true || { echo "Can't run as $user, see the setup at the top of $0." >&2; exit 1; }

# The test user can't read our home, so it runs a copy.
rsync -a --delete "$larbsdir/" "$copy/" && chmod -R a+rwX "$copy"

# brew is ours, so for the test user it's read-only: Brewfile installs fail, which LARBS continues past.
as env PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
	HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_BUNDLE_NO_LOCK=1 \
	sh "$copy/larbs.sh" -r "$repo" </dev/null

echo "
Checks:"
as env PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" sh -s <<'EOF'
fails=0
t() { # <exit code> <description>
	if [ "$1" = 0 ]; then echo "  ok    $2"; else echo "  FAIL  $2"; fails=$((fails + 1)); fi
}
dotfiles() { git -C "$HOME" --git-dir="$HOME/.dotfiles" --work-tree="$HOME" "$@"; }
hotkey() { defaults export com.apple.symbolichotkeys - | plutil -extract "AppleSymbolicHotKeys.$1.enabled" raw -o - -; }

[ -f ~/.dotfiles/HEAD ]; t $? "dotfiles' git dir is ~/.dotfiles"
[ "$(dotfiles rev-parse --abbrev-ref '@{u}' 2>/dev/null)" = origin/master ]; t $? "master tracks origin/master"
[ -z "$(dotfiles status --porcelain -uno 2>&1)" ]; t $? "tracked files all in place"
! dotfiles submodule status 2>&1 | grep -q '^[-+U]\|fatal'; t $? "submodules checked out"

s="$(readlink ~/.config/yabai/skhdrc-spaces)"
[ "$s" = skhdrc-spaces-native ] || [ "$s" = skhdrc-spaces-yabai ]; t $? "skhd spaces bindings linked ($s)"
[ "$(defaults read com.apple.dock mru-spaces)" = 0 ]; t $? "dock doesn't rearrange spaces"
[ "$(hotkey 32)" = true ] && [ "$(hotkey 79)" = false ] && [ "$(hotkey 81)" = false ]
t $? "mission control on opt+up, move a space left/right disabled"
[ "$(defaults read com.googlecode.iterm2 PrefsCustomFolder)" = "$HOME/.config/iterm" ]; t $? "iterm loads ~/.config/iterm"

gist=~/.cache/larbs/vscode-settings
for x in codium:VSCodium cursor:Cursor code:Code code-insiders:"Code - Insiders" windsurf:Windsurf; do
	command -v "${x%%:*}" >/dev/null || continue
	u="$HOME/Library/Application Support/${x#*:}/User"
	cmp -s "$u/settings.json" "$gist/settings.json" && cmp -s "$u/keybindings.json" "$gist/keybindingsMac.json"
	t $? "${x#*:}: settings & keybindings = gist"
	# anysphere.* are cursor's own, see vscode.sh
	missing="$(sed -n 's/.*"publisherId": *"\([^"]*\)".*/\1/p' "$gist/extensions.json" | tr '[:upper:]' '[:lower:]' |
		if [ "${x%%:*}" = cursor ]; then cat; else grep -v '^anysphere\.'; fi |
		grep -vxF "$("${x%%:*}" --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]')" | tr '\n' ' ')"
	[ -z "$missing" ] || echo "        extensions not installed: $missing"
done

echo
[ "$fails" = 0 ] && echo "All checks passed." || echo "$fails check(s) failed."
exit "$fails"
EOF
