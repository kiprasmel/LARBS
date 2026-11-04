#!/bin/sh

# Runs LARBS (this working tree, uncommitted changes included) as a throwaway, non-admin macOS user,
# then checks the result.
#
# usage: testing/macos.sh [--no-cleanup | --cleanup] [dotfiles repo]
#   by default, creates the user, runs & checks, then deletes the user: a fresh install every time.
#   --no-cleanup: keep the user, so the next run tests a re-run (safe to re-run is a LARBS promise).
#   --cleanup: only delete the user.
#
# Creating & deleting the user needs sudo, i.e. your password. While the user exists, a sudoers rule
# lets you run things *as it* (only) w/o a password, so runs w/ --no-cleanup don't need sudo.
# Agents can't type the password: ask the user to run this w/ --no-cleanup once, then run it w/
# --no-cleanup yourself as often as needed, and ask the user to run it w/ --cleanup at the end.
#
# Expected in the output, not failures of LARBS (the user isn't logged in at the screen, and doesn't own brew):
# - "Failed to install ..." / "Permission denied ... /opt/homebrew/...": brew belongs to you, so it's read-only for
#   the test user, and LARBS continues past Brewfile failures.
# - ssh-keygen stops at its first prompt: there's no terminal to type into.
# - yabai/skhd "Bootstrap failed: 125": services can't start w/o a login session.
# - Code - Insiders: "failed to install ... KylinIDETeam.gitlens": that fork is only on open-vsx, not on MS' marketplace.
# - shortcuts are written but apply only at the user's next login (see applyhotkeys in macos-lib.sh).

user=larbstest
cleanup=1
case "$1" in
--no-cleanup) cleanup= && shift ;;
--cleanup) cleanup=only && shift ;;
esac
repo="${1:-https://github.com/kiprasmel/voidrice}"
larbsdir="$(cd "$(dirname "$0")/.." && pwd)"
copy="/Users/Shared/larbs-test"

as() { (cd / && sudo -n -u "$user" -H "$@"); }

setup() {
	as true 2>/dev/null && return
	echo "Creating the test user $user (needs sudo)."
	# nobody logs in as it, so a random password
	id "$user" >/dev/null 2>&1 ||
		sudo sysadminctl -addUser "$user" -fullName "LARBS test" -password "$(openssl rand -hex 16)" || return 1
	sudo createhomedir -c -u "$user" >/dev/null
	rule="$(mktemp)"
	echo "#$(id -u) ALL=($user) NOPASSWD: ALL" >"$rule"
	sudo visudo -cf "$rule" >/dev/null && sudo install -m 0440 -o root -g wheel "$rule" "/etc/sudoers.d/$user"
	rm -f "$rule"
	as true
}

deleteuser() {
	rm -rf "$copy"
	id "$user" >/dev/null 2>&1 || return 0
	echo "Deleting the test user $user (needs sudo)."
	sudo sysadminctl -deleteUser "$user" && sudo rm -f "/etc/sudoers.d/$user"
}

[ "$cleanup" = only ] && { deleteuser; exit; }

setup || { echo "Can't create or run as $user." >&2; exit 1; }

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
fails=$?
echo "(brew permission errors, ssh-keygen, yabai/skhd bootstrap errors above are expected, see the top of $0)"

[ -n "$cleanup" ] && deleteuser
exit "$fails"
