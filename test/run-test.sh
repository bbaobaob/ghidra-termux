#!/usr/bin/env bash
# run-test.sh -- end-to-end smoke test for the ghidra-termux port.
# Builds a tiny ARM64 binary, imports + analyzes + decompiles it headless, and
# verifies the decompiled C output actually contains our functions.
set -euo pipefail

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
GHIDRA="${GHIDRA_TERMUX_HOME:-$PREFIX/opt/ghidra-termux}"
LAUNCHER="$PREFIX/bin/ghidra-termux"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

say() { echo; echo "### $*"; }

say "1/5 building test binary"
if command -v gcc >/dev/null; then CC=gcc; else CC=clang; fi
$CC -O1 -o "$WORK/test-target" "$HERE/target.c"
file "$WORK/test-target" | sed 's/^/    /'

run_ghidra() {
  if [ -x "$LAUNCHER" ]; then
    "$LAUNCHER" "$@"
  else
    "$GHIDRA/support/analyzeHeadless" "$@"
  fi
}

say "2/5 headless import + analyze + decompile"
mkdir -p "$WORK/proj"
time run_ghidra "$WORK/proj" test -import "$WORK/test-target" \
  -processor AARCH64:LE:64:default \
  -scriptPath "$HERE" -postScript DecompileAll.java "$WORK/out.c"

say "3/5 checking decompiler output"
[ -s "$WORK/out.c" ] || { echo "FAIL: $WORK/out.c empty"; exit 1; }
grep -q "factorial" "$WORK/out.c" || { echo "FAIL: factorial not decompiled"; exit 1; }
grep -q "classify"   "$WORK/out.c" || { echo "FAIL: classify not decompiled"; exit 1; }
grep -q "FAILED" "$WORK/out.c" && { echo "FAIL: some functions failed to decompile"; exit 1; }
echo "    decompiled functions: $(grep -c '^// ====' "$WORK/out.c")"
echo "    output size: $(wc -c < "$WORK/out.c") bytes"

say "4/5 sample output (main)"
awk '/^\/\/ ==== main /,/^\/\/ ==== [^m]/' "$WORK/out.c" | head -30 | sed 's/^/    /'

say "5/5 second pass: -process -noanalysis (re-run speed)"
start=$(date +%s)
run_ghidra "$WORK/proj" test -process test-target -noanalysis \
  -scriptPath "$HERE" -postScript DecompileAll.java "$WORK/out2.c" >/dev/null 2>&1
echo "    second pass took $(( $(date +%s) - start ))s"

echo
echo "ALL TESTS PASSED"
