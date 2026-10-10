#!/usr/bin/env bash
# build-natives.sh -- build Ghidra's native decompiler (decompile + sleigh) for
# linux_arm_64 directly on the device with Termux clang.
#
# Official Ghidra releases only ship linux_x86_64/win_x86_64 natives, so ARM64
# users must supply their own. This is the on-device fallback when the prebuilt
# binaries from GitHub Releases (installed by install.sh) are unavailable.
#
# Requirements: pkg install clang make
# Takes ~5-15 min on a modern phone (115 C++ files).

set -euo pipefail

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
GHIDRA_HOME="${GHIDRA_TERMUX_HOME:-$PREFIX/opt/ghidra-termux}"
CPP="$GHIDRA_HOME/Ghidra/Features/Decompiler/src/decompile/cpp"
DEST="$GHIDRA_HOME/Ghidra/Features/Decompiler/os/linux_arm_64"

[ -d "$CPP" ] || { echo "build-natives: '$CPP' not found (is Ghidra installed?)" >&2; exit 1; }
command -v make >/dev/null 2>&1 || { echo "build-natives: run 'pkg install make'" >&2; exit 1; }
if ! command -v g++ >/dev/null 2>&1 && ! command -v clang++ >/dev/null 2>&1; then
  echo "build-natives: run 'pkg install clang'" >&2
  exit 1
fi

JOBS="${JOBS:-$(nproc)}"
echo "build-natives: compiling 115 C++ files with -j$JOBS (be patient)..."

cd "$CPP"

# The upstream Makefile hardcodes ARCH_TYPE=-m32 for every non-x86_64 Linux
# (see its TODO about aarch64). A command-line variable assignment overrides an
# in-Makefile assignment, so `ARCH_TYPE=` (empty) strips the bogus -m32.
#
# EXTRA= removes the binutils/BFD-dependent files (bfd_arch.cc, loadimage_bfd.cc,
# analyzesigs.cc) that the default dependency target would otherwise try to
# compile; they need bfd.h from binutils-dev, which Termux does not ship, and
# neither the gradle build nor Ghidra itself needs them at runtime.
# Generated parser sources (slghparse.cc/slghscan.cc) ship with the release,
# so no flex/bison needed. sleigh links against zlib (-lz).
make -j"$JOBS" ghidra_opt sleigh_opt ARCH_TYPE= EXTRA=

mkdir -p "$DEST"
install -m 755 ghidra_opt "$DEST/decompile"
install -m 755 sleigh_opt  "$DEST/sleigh"

echo "build-natives: installed:"
echo "  $DEST/decompile"
echo "  $DEST/sleigh"
