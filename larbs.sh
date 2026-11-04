#!/bin/sh

# Luke's Auto Rice Boostrapping Script (LARBS)
# by Luke Smith <luke@lukesmith.xyz>
# License: GNU GPLv3

# Entrypoint: detects the OS and runs arch.sh or macos.sh, passing all arguments through.
# Works standalone (`curl -LO .../larbs.sh`): the other scripts are fetched from the repo.

larbsrepo="https://github.com/kiprasmel/LARBS"
larbsraw="https://raw.githubusercontent.com/kiprasmel/LARBS/master"

error() {
	# Log to stderr and exit with failure.
	printf "%s\n" "$1" >&2
	exit 1
}

scriptdir="$(cd "$(dirname "$0")" && pwd)"

case "$(uname -s)" in
Darwin)
	# macos.sh needs the rest of the repo (Brewfile, macos-*.sh), so clone it into ~/LARBS.
	larbsdir="$scriptdir"
	if [ ! -f "$larbsdir/macos.sh" ]; then
		larbsdir="$HOME/LARBS"
		# A fresh macOS has no git until the command line tools are installed.
		xcode-select -p >/dev/null 2>&1 || {
			xcode-select --install
			error "Install the command line tools in the dialog that opened, then re-run larbs.sh."
		}
		[ -d "$larbsdir" ] || git clone "$larbsrepo" "$larbsdir" || error "Failed to clone $larbsrepo."
	fi
	exec sh "$larbsdir/macos.sh" "$@"
	;;
Linux)
	command -v pacman >/dev/null 2>&1 || error "On Linux, only Arch-based distributions are supported."
	[ -f "$scriptdir/arch.sh" ] && exec sh "$scriptdir/arch.sh" "$@"
	archsh="$(mktemp)"
	curl -Ls "$larbsraw/arch.sh" >"$archsh" || error "Failed to download arch.sh."
	exec sh "$archsh" "$@"
	;;
*)
	error "Unsupported OS: $(uname -s)."
	;;
esac
