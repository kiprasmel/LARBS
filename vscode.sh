#!/bin/sh

# Applies the vscode settings from the gist to every installed flavor (vscodium, cursor, vscode,
# vscode insiders, windsurf): settings.json, keybindings.json (keybindingsMac.json on macOS), and
# extensions.json (extensions-disabled.json & extensions-404.json are left out). For cursor also its
# "Terminal" profile, see profile-terminal.md in the gist.
#
# When a file has local changes that aren't in the gist, asks whether to override it (w/ a backup),
# merge (3-way against the gist version last applied here, leaving conflict markers to resolve,
# e.g. by an agent), or skip. Works on macOS and Linux. Safe to re-run.

### OPTIONS AND VARIABLES ###

while getopts ":m:Eh" o; do case "${o}" in
	h) printf "Usage: vscode.sh [-m ask|override|merge|skip] [-E] [flavor...]\\n  -m: What to do w/ files that have local changes. Default: ask\\n  -E: Don't install extensions\\n  flavors: vscodium cursor vscode vscode-insiders windsurf. Default: all installed\\n" && exit ;;
	m) mode=${OPTARG} ;;
	E) noextensions=1 ;;
	*) printf "Invalid option: -%s\\n" "$OPTARG" && exit 1 ;;
esac done
shift $((OPTIND - 1))

[ -z "$mode" ] && mode=ask
case "$mode" in ask | override | merge | skip) ;; *) printf "Invalid mode: %s\\n" "$mode" && exit 1 ;; esac

gist="https://gist.github.com/kiprasmel/de9160a0602463fb752f2d84d7aa4fd8"
gistdir="${XDG_CACHE_HOME:-$HOME/.cache}/larbs/vscode-settings"
# The gist version last applied to each file, i.e. the merge base for the next run.
statedir="${XDG_STATE_HOME:-$HOME/.local/state}/larbs/vscode"

case "$(uname -s)" in
Darwin) appsupport="$HOME/Library/Application Support" keybindings=keybindingsMac.json ;;
*) appsupport="${XDG_CONFIG_HOME:-$HOME/.config}" keybindings=keybindings.json ;;
esac

conflicts=""
skipped=""

### FUNCTIONS ###

error() {
	# Log to stderr and exit with failure.
	printf "%s\n" "$1" >&2
	exit 1
}

flavorinfo() { # <flavor> -> "<user data dir>:<cli>"
	case "$1" in
	vscodium) echo "VSCodium:codium" ;;
	cursor) echo "Cursor:cursor" ;;
	vscode) echo "Code:code" ;;
	vscode-insiders) echo "Code - Insiders:code-insiders" ;;
	windsurf) echo "Windsurf:windsurf" ;;
	*) return 1 ;;
	esac
}

fetchgist() {
	if [ -d "$gistdir/.git" ]; then
		git -C "$gistdir" pull -q --ff-only || echo "Couldn't update the gist, using the cached one." >&2
	else
		mkdir -p "$(dirname "$gistdir")" && git clone -q "$gist.git" "$gistdir"
	fi
}

jsonc() { # <diff <local> <gist> | themeextensions <settings.json> <extensions dir>>
	# diff: lists what's in the local jsonc file but not in the gist's (keys w/ other values, or array entries),
	#   so local settings that the gist already has don't count as changes. Fails if there's anything.
	# themeextensions: lists the installed extensions that provide the color/icon/product icon themes the settings use.
	python3 -I - "$@" <<'EOF'
import glob, json, os, re, sys

def load(path):
    # jsonc -> json: drop comments & trailing commas, outside of strings.
    s = open(path, encoding="utf-8").read()
    segments, rest, i = [], [], 0
    while i < len(s):
        if s[i] == '"':
            j = i + 1
            while j < len(s) and s[j] != '"':
                j += 2 if s[j] == "\\" else 1
            segments += [re.sub(r",(\s*[}\]])", r"\1", "".join(rest)), s[i:j + 1]]
            rest, i = [], j + 1
        elif s.startswith("//", i):
            j = s.find("\n", i)
            i = len(s) if j < 0 else j
        elif s.startswith("/*", i):
            j = s.find("*/", i + 2)
            i = len(s) if j < 0 else j + 2
        else:
            rest.append(s[i])
            i += 1
    text = "".join(segments) + re.sub(r",(\s*[}\]])", r"\1", "".join(rest))
    return json.loads(text) if text.strip() else None

def diff(local_path, gist_path):
    try:
        local, gist = load(local_path), load(gist_path)
    except Exception as e:
        print(f"can't parse ({e})")
        return 1
    if local is None:
        changes = []
    elif isinstance(local, dict) and isinstance(gist, dict):
        changes = [("changed: " if k in gist else "local only: ") + k for k in local if gist.get(k, object()) != local[k]]
    elif isinstance(local, list) and isinstance(gist, list):
        changes = ["local only: " + json.dumps(e, separators=(",", ":")) for e in local if e not in gist]
    else:
        changes = ["different structure"]
    print("\n".join(changes))
    return 1 if changes else 0

def themeextensions(settings_path, extensions_dir):
    try:
        settings = load(settings_path) or {}
    except Exception:
        return 0
    contributes = {"colorTheme": "themes", "iconTheme": "iconThemes", "productIconTheme": "productIconThemes"}
    wanted = {kind: settings.get("workbench." + setting) for setting, kind in contributes.items()}
    for path in glob.glob(os.path.join(extensions_dir, "*", "package.json")):
        try:
            pkg = json.load(open(path, encoding="utf-8"))
        except Exception:
            continue
        themes = pkg.get("contributes", {})
        if any(theme and any(theme in (t.get("id"), t.get("label")) for t in themes.get(kind, []))
               for kind, theme in wanted.items()):
            print(f'{pkg["publisher"]}.{pkg["name"]}')
    return 0

sys.exit({"diff": diff, "themeextensions": themeextensions}[sys.argv[1]](*sys.argv[2:]))
EOF
}

choose() { # <allowed choices, e.g. "oms"> <file> <gist file> -> sets $choice
	choice="$mode"
	case "$choice" in merge) case "$1" in *m*) ;; *) choice=skip ;; esac ;; esac
	while [ "$choice" = ask ]; do
		(: </dev/tty) 2>/dev/null || { choice=skip && break; } # not interactive
		case "$1" in
		*m*) printf "    [o]verride (w/ backup), [m]erge (leaves conflicts to resolve), [d]iff, [s]kip? " >/dev/tty ;;
		*) printf "    [o]verride (w/ backup), [d]iff, [s]kip? " >/dev/tty ;;
		esac
		read -r answer </dev/tty
		case "$answer" in
		o*) choice=override ;;
		m*) case "$1" in *m*) choice=merge ;; esac ;;
		s*) choice=skip ;;
		d*) diff -u "$2" "$3" | ${PAGER:-less} ;;
		esac
	done
}

backup() { # <file>
	[ -e "$1" ] || return 0
	cp "$1" "$1.larbs-backup-$(date +%Y%m%d-%H%M%S)" && echo "    backed up to $1.larbs-backup-*"
}

applyfile() { # <file> <gist file> <base>
	file="$1" src="$2" base="$3"
	name="${file#"$appsupport/"}"
	mkdir -p "$(dirname "$file")" "$(dirname "$base")"
	if [ ! -s "$file" ]; then
		cp "$src" "$file" && echo "  $name: installed"
	elif cmp -s "$file" "$src"; then
		echo "  $name: up to date"
	elif [ -f "$base" ] && cmp -s "$src" "$base"; then
		echo "  $name: has local changes, the gist hasn't changed since last applied. Keeping them."
		return
	elif [ -f "$base" ] && cmp -s "$file" "$base"; then
		cp "$src" "$file" && echo "  $name: updated"
	elif jsonc diff "$file" "$src" >/dev/null; then
		echo "  $name: local settings are all in the gist already, replacing"
		backup "$file"
		cp "$src" "$file"
	else
		if [ -f "$base" ]; then
			echo "  $name: has local changes since last applied, and the gist changed too. Local changes:"
			jsonc diff "$file" "$base" | head -20 | sed 's/^/    /'
		else
			echo "  $name: has local changes that aren't in the gist:"
			jsonc diff "$file" "$src" | head -20 | sed 's/^/    /'
		fi
		choose oms "$file" "$src"
		case "$choice" in
		override)
			backup "$file"
			cp "$src" "$file" && echo "    overridden"
			;;
		merge)
			backup "$file"
			# No base yet: 2-way merge against an empty file, so every difference is a conflict.
			mergebase="$base"
			[ -f "$base" ] || mergebase="$(mktemp)"
			git merge-file -L local -L "last applied" -L gist "$file" "$mergebase" "$src"
			n=$?
			[ "$mergebase" = "$base" ] || rm -f "$mergebase"
			if [ $n -eq 0 ]; then
				echo "    merged cleanly"
			else
				echo "    merged w/ $n conflict(s) left"
				conflicts="$conflicts
  $file"
			fi
			;;
		*)
			echo "    skipped"
			skipped="$skipped
  $file"
			return
			;;
		esac
	fi
	cp "$src" "$base"
}

installextensions() { # <cli> <profile, or ""> <extension ids or .vsix paths...>
	cli="$1" profile="$2"
	shift 2
	installed="$("$cli" ${profile:+--profile "$profile"} --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]')"
	failed=""
	for ext; do
		case "$ext" in
		*.vsix)
			[ -f "$ext" ] || { failed="$failed $ext (missing)" && continue; }
			# e.g. terminal-title-context-0.0.1.vsix -> *.terminal-title-context
			id="$(basename "$ext" .vsix | sed 's/-[0-9][0-9.]*$//' | tr '[:upper:]' '[:lower:]')"
			echo "$installed" | grep -q "\.$id$" && continue
			;;
		*)
			echo "$installed" | grep -qxF "$(echo "$ext" | tr '[:upper:]' '[:lower:]')" && continue
			;;
		esac
		"$cli" ${profile:+--profile "$profile"} --install-extension "$ext" >/dev/null 2>&1 &&
			echo "  extension installed${profile:+ ($profile profile)}: $ext" ||
			failed="$failed $ext"
	done
	[ -z "$failed" ] || echo "  extensions that failed to install${profile:+ ($profile profile)}, e.g. not in this flavor's marketplace:$failed"
}

cursorterminalprofile() { # <user dir>
	# The "Terminal" profile shares the default profile's settings & keybindings via symlinks,
	# and has its own lean extensions. See profile-terminal.md in the gist.
	userdir="$1"
	location="$(python3 -I -c 'import json, sys
for p in json.load(open(sys.argv[1])).get("userDataProfiles", []):
    if p.get("name") == "Terminal": print(p["location"])' "$userdir/globalStorage/storage.json" 2>/dev/null)"
	if [ -z "$location" ]; then
		echo "  Terminal profile: missing. Create it w/ \`cursor --profile Terminal --new-window\` and re-run."
		return
	fi
	profiledir="$userdir/profiles/$location"
	for f in settings.json keybindings.json; do
		[ "$(readlink "$profiledir/$f")" = "$userdir/$f" ] && echo "  Terminal profile $f: linked" && continue
		if [ -s "$profiledir/$f" ] && ! cmp -s "$profiledir/$f" "$userdir/$f" &&
			! jsonc diff "$profiledir/$f" "$userdir/$f" >/dev/null; then
			echo "  Terminal profile $f: has local changes that aren't in the default profile's:"
			jsonc diff "$profiledir/$f" "$userdir/$f" | head -20 | sed 's/^/    /'
			choose os "$profiledir/$f" "$userdir/$f"
			if [ "$choice" != override ]; then
				echo "    skipped"
				skipped="$skipped
  $profiledir/$f"
				continue
			fi
		fi
		backup "$profiledir/$f"
		mkdir -p "$profiledir"
		ln -sfn "$userdir/$f" "$profiledir/$f" && echo "  Terminal profile $f: linked to the default profile's"
	done
	[ -n "$noextensions" ] && return
	# Its extensions are listed as install commands in the md. Plus the theme ones, since the settings are shared.
	# shellcheck disable=SC2046 # one id or path per line, w/o spaces
	installextensions cursor Terminal $(sed -n "/^ *cursor --profile Terminal --install-extension /{s|||;s|^~/|$HOME/|;p;}" "$gistdir/profile-terminal.md") \
		$(jsonc themeextensions "$userdir/settings.json" "$HOME/.cursor/extensions")
}

### THE ACTUAL SCRIPT ###

fetchgist || error "Failed to fetch the gist: $gist"

[ $# -eq 0 ] && set -- vscodium cursor vscode vscode-insiders windsurf
for flavor; do
	info="$(flavorinfo "$flavor")" || { echo "Unknown flavor: $flavor" >&2 && continue; }
	dir="${info%:*}" flavorcli="${info##*:}"
	# Installed: has its cli or its user data dir.
	command -v "$flavorcli" >/dev/null 2>&1 || [ -d "$appsupport/$dir" ] || continue
	echo "$dir:"
	applyfile "$appsupport/$dir/User/settings.json" "$gistdir/settings.json" "$statedir/$flavor/settings.json"
	applyfile "$appsupport/$dir/User/keybindings.json" "$gistdir/$keybindings" "$statedir/$flavor/keybindings.json"
	if [ -z "$noextensions" ] && command -v "$flavorcli" >/dev/null 2>&1; then
		extensions="$(sed -n 's/.*"publisherId": *"\([^"]*\)".*/\1/p' "$gistdir/extensions.json")"
		# anysphere.* are cursor's own (remote ssh/containers).
		[ "$flavor" = cursor ] || extensions="$(echo "$extensions" | grep -v '^anysphere\.')"
		# shellcheck disable=SC2086 # one id per line
		installextensions "$flavorcli" "" $extensions
	fi
	# After the default profile's extensions, which provide the themes its Terminal profile needs.
	[ "$flavor" != cursor ] || cursorterminalprofile "$appsupport/$dir/User"
done

[ -z "$skipped" ] || echo "
Skipped, w/ local changes:$skipped
Re-run to decide again, or w/ -m override|merge."
[ -z "$conflicts" ] || echo "
Resolve the conflict markers (<<<<<<< local / >>>>>>> gist) in:$conflicts
e.g. tell an agent: finish the merge in these files, keeping local changes unless the gist ($gist) supersedes them."
