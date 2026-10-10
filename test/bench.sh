#!/usr/bin/env bash
# bench.sh -- measure ghidra-termux analysis performance on this device.
#
# Matrix:
#   1. warmup (SLEIGH spec cache) then cold-ish full analysis baseline
#   2. GHIDRA_TERMUX_CORES=4 vs 8        (big.LITTLE thread-pool cap)
#   3. SerialGC (default) vs G1GC
#   4. batch import (N binaries, 1 JVM) vs N separate invocations
#
# Usage: bash bench.sh [binary]     (builds a synthetic target if none given)
set -euo pipefail

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
LAUNCHER="${GHIDRA_TERMUX_BIN:-$PREFIX/bin/ghidra-termux}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

say() { echo; echo "### $*"; }

# ------------------------------------------------------- synthetic target ----
make_target() {
  local out="$1" n="${2:-200}"
  {
    echo '#include <stdio.h>'
    echo '#include <string.h>'
    echo '#include <stdlib.h>'
    for i in $(seq 0 $((n - 1))); do
      cat <<EOF
int fn_$i(int a, int b) {
    int s = a + b;
    for (int j = 0; j < $((i % 7 + 1)); j++) { s += j * $i; if (s > 1000) s -= 500; }
    switch (s % 5) { case 0: s += 1; break; case 1: s += 2; break; default: s += 3; }
    return s;
}
EOF
    done
    echo 'int main(int argc, char **argv) {'
    echo '    int t = 0;'
    for i in $(seq 0 19); do echo "    t += fn_$i(argc, t);"; done
    echo '    printf("%d\n", t);'
    echo '    return t & 0xff;'
    echo '}'
  } > "$out.c"
  if command -v gcc >/dev/null; then CC=gcc; else CC=clang; fi
  $CC -O1 -o "$out" "$out.c"
}

say "preparing benchmark target (~200 functions)"
TARGET="$WORK/bench-target"
if [ $# -ge 1 ] && [ -f "$1" ]; then
  TARGET="$1"
else
  make_target "$TARGET" 200
fi
ls -la "$TARGET" | awk '{print "    size:", $5, "bytes"}'
BINDIR="$WORK/batch"; mkdir -p "$BINDIR"
for i in 1 2 3 4 5; do cp "$TARGET" "$BINDIR/t$i"; done

run_timed() {  # run_timed <label> <extra-env-assignments...> -- <args...>
  local label="$1"; shift
  local envs=() ; while [ "$1" != "--" ]; do envs+=("$1"); shift; done; shift
  local proj="$WORK/proj-$RANDOM"; mkdir -p "$proj"
  local start end ms
  start=$(date +%s%N)
  env "${envs[@]}" "$LAUNCHER" "$proj" bench -import "$@" \
    -processor AARCH64:LE:64:default -analysisTimeoutPerFile 600 \
    >"$WORK/last.log" 2>&1 || { echo "    FAILED (see $WORK/last.log)"; tail -5 "$WORK/last.log"; return 1; }
  end=$(date +%s%N)
  ms=$(( (end - start) / 1000000 ))
  printf "    %-42s %6d.%03d s\n" "$label" "$((ms / 1000))" "$((ms % 1000))"
}

say "0/4 warmup (compiles SLEIGH specs, results discarded)"
PROJ="$WORK/warm"; mkdir -p "$PROJ"
"$LAUNCHER" "$PROJ" warm -import "$TARGET" -processor AARCH64:LE:64:default \
  -analysisTimeoutPerFile 600 >/dev/null 2>&1 || echo "    warmup failed"

say "1/4 thread-pool cap: cores 4 vs 8"
run_timed "GHIDRA_TERMUX_CORES=4" GHIDRA_TERMUX_CORES=4 -- "$TARGET"
run_timed "GHIDRA_TERMUX_CORES=8" GHIDRA_TERMUX_CORES=8 -- "$TARGET"

say "2/4 GC: SerialGC (default) vs G1GC"
run_timed "SerialGC (wrapper default)" -- "$TARGET"
run_timed "G1GC" GHIDRA_JAVA_OPTIONS="-XX:+UseG1GC" -- "$TARGET"

say "3/4 batch vs separate invocations"
run_timed "batch: 5 binaries in 1 JVM" -- "$BINDIR" -recursive
for i in 1 2 3 4 5; do
  run_timed "separate run $i/5" -- "$BINDIR/t$i"
done

echo
echo "benchmark done"
