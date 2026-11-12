#!/bin/sh
# Install the UpNote MCP server for the current user.
#
# What it does:
#   1. Makes ~/.claude/mcp-servers/upnote-mcp point to this folder (if it does not exist).
#   2. Builds a virtual environment from python.org's Python 3.12 or newer.
#   3. Compiles and signs the launcher, the program that gets the Full Disk Access grant.
# It does not change any client setting. It prints the commands for that at the end.
#
# Set PYTHON to the path of a python.org Python 3.12+ to override the search.

set -eu

BASE="$HOME/.claude/mcp-servers"
TARGET="$BASE/upnote-mcp"
VENV="$BASE/upnote-mcp-venv"
LAUNCHER="$BASE/upnote-mcp-launcher"
MCP_VERSION="2.2.0" # keep in step with server.py's "dependencies" line

SELF=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)

die() { echo "install.sh: $*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "macOS only."
command -v clang >/dev/null 2>&1 || die "clang not found. Run: xcode-select --install"
command -v codesign >/dev/null 2>&1 || die "codesign not found."
[ -f "$SELF/server.py" ] && [ -f "$SELF/launcher.c" ] || die "run this script from a full checkout."

# 1. Package link
mkdir -p "$BASE"
if [ -e "$TARGET" ] || [ -L "$TARGET" ]; then
    CURRENT=$(CDPATH= cd -- "$TARGET" 2>/dev/null && pwd -P) || CURRENT=""
    [ "$CURRENT" = "$SELF" ] || die "$TARGET already exists and is not this folder ($CURRENT). Move it away or see README 'Upgrading'."
else
    ln -s "$SELF" "$TARGET"
    echo "Linked $TARGET -> $SELF"
fi

# 2. Python
if [ -z "${PYTHON:-}" ]; then
    for v in 3.14 3.13 3.12; do
        c="/Library/Frameworks/Python.framework/Versions/$v/bin/python$v"
        if [ -x "$c" ]; then PYTHON="$c"; break; fi
    done
fi
[ -n "${PYTHON:-}" ] || die "no python.org Python 3.12+ found. Install it from https://www.python.org/downloads/macos/ or set PYTHON."
"$PYTHON" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 12) else 1)' || die "$PYTHON is older than 3.12."

if [ ! -x "$VENV/bin/python" ]; then
    "$PYTHON" -m venv "$VENV"
fi
"$VENV/bin/python" -m pip install --quiet --disable-pip-version-check "mcp==$MCP_VERSION"

# 3. Launcher
clang -O2 -o "$LAUNCHER" "$SELF/launcher.c"
codesign -s - -i ca.glotov.upnote-mcp-launcher -f "$LAUNCHER"

cat <<EOF

Installed.

Next steps:
  1. Grant Full Disk Access to the launcher (System Settings > Privacy & Security >
     Full Disk Access > +, then press Cmd+Shift+G and paste the path):
       $LAUNCHER
  2. Register it with your client:
       claude mcp add --scope user upnote -- $LAUNCHER
       codex mcp add upnote -- $LAUNCHER
     For Claude Desktop, see the README ("Claude Desktop").
  3. Restart the client and ask Claude to run check_upnote_setup.
EOF
