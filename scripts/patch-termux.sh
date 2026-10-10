#!/usr/bin/env bash
# patch-termux.sh -- patch a stock Ghidra install so it runs under Termux.
#
# Termux has no /usr/bin, /bin or /usr/bin/env, so every absolute-path shebang
# in a stock Ghidra release is broken on Android. This script rewrites them to
# $PREFIX. It is idempotent (safe to re-run) and only ever touches line 1 of
# files that actually start with a shebang.
#
# Usage: patch-termux.sh [ghidra-install-dir]
#   default: $PREFIX/opt/ghidra-termux  (or $GHIDRA_TERMUX_HOME)

set -euo pipefail

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
GHIDRA_HOME="${1:-${GHIDRA_TERMUX_HOME:-$PREFIX/opt/ghidra-termux}}"

if [ ! -d "$GHIDRA_HOME/support" ]; then
  echo "patch-termux: '$GHIDRA_HOME' does not look like a Ghidra install (no support/ dir)" >&2
  exit 1
fi

BASH="$PREFIX/bin/bash"
SH="$PREFIX/bin/sh"

rewrite() {
  # $1 = grep pattern (ERE, matched against the first line), rest = sed expressions
  local pat="$1"; shift
  local f first
  while IFS= read -r f; do
    first="$(head -n 1 "$f" 2>/dev/null || true)"
    case "$first" in
      '#!'*)
        # sed only rewrites line 1 when it matches; other files are untouched.
        sed -i "$@" "$f"
        ;;
    esac
  done < <(grep -rlIE "$pat" "$GHIDRA_HOME" 2>/dev/null || true)
}

echo "patch-termux: patching shebangs under $GHIDRA_HOME"

# bash: #!/usr/bin/env bash, #!/bin/bash
rewrite '^#!.*(env[[:space:]]+bash|/bin/bash)' \
  -e "1s|^#!.*env[[:space:]]\+bash.*|#!$BASH|" \
  -e "1s|^#!/bin/bash.*|#!$BASH|"

# sh: #!/usr/bin/env sh, #!/bin/sh
rewrite '^#!.*(env[[:space:]]+sh|/bin/sh)' \
  -e "1s|^#!.*env[[:space:]]\+sh.*|#!$SH|" \
  -e "1s|^#!/bin/sh.*|#!$SH|"

# python (only if a python3 exists; PyGhidra's setup.py is the only affected file)
if [ -x "$PREFIX/bin/python3" ]; then
  rewrite '^#!.*python' -e "1s|^#!.*python.*|#!$PREFIX/bin/python3|"
fi

# Ghidra expects these to be executable
chmod +x "$GHIDRA_HOME"/support/analyzeHeadless "$GHIDRA_HOME"/support/launch.sh 2>/dev/null || true

echo "patch-termux: done"
