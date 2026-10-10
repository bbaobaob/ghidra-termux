#!/usr/bin/env bash
# build-deb.sh -- package a prepared ghidra-termux install tree as a Termux .deb
#
# Usage: build-deb.sh [ghidra-install-dir] [output.deb]
#   ghidra-install-dir  default: $PREFIX/opt/ghidra-termux
#   output.deb          default: ./ghidra-termux_<version>_aarch64.deb
#
# The .deb uses the standard Termux layout: everything under
# data/data/com.termux/files/usr/..., which dpkg installs into $PREFIX.
# Install with:  dpkg -i ghidra-termux_12.1.4_aarch64.deb
#           or:  pkg install ./ghidra-termux_12.1.4_aarch64.deb   (resolves deps)

set -euo pipefail

VERSION="12.1.4"
ARCH="aarch64"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

SRC="${1:-$PREFIX/opt/ghidra-termux}"
OUT="${2:-$REPO_DIR/ghidra-termux_${VERSION}_${ARCH}.deb}"

[ -d "$SRC/support" ] || { echo "build-deb: '$SRC' is not a Ghidra install (no support/)" >&2; exit 1; }
[ -x "$SRC/Ghidra/Features/Decompiler/os/linux_arm_64/decompile" ] || {
  echo "build-deb: WARNING: no ARM64 natives in $SRC (decompilation will not work)" >&2
}

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

ROOT="$STAGE/data/data/com.termux/files/usr"

echo "build-deb: staging $SRC -> $OUT"
mkdir -p "$ROOT/opt" "$ROOT/bin" "$ROOT/share/ghidra-termux"

cp -a "$SRC" "$ROOT/opt/ghidra-termux"
install -m 755 "$REPO_DIR/scripts/ghidra-termux" "$ROOT/bin/ghidra-termux"
ln -sf ghidra-termux "$ROOT/bin/ghidra"

# test suite + docs ride along under share/
mkdir -p "$ROOT/share/ghidra-termux"
cp -a "$REPO_DIR/test" "$ROOT/share/ghidra-termux/test"
[ -d "$REPO_DIR/docs" ] && cp -a "$REPO_DIR/docs" "$ROOT/share/ghidra-termux/docs"
cp -a "$REPO_DIR/README.md" "$ROOT/share/ghidra-termux/README.md" 2>/dev/null || true

INSTALLED_SIZE=$(( $(du -sk "$ROOT" | cut -f1) ))

mkdir -p "$STAGE/DEBIAN"
chmod 755 "$STAGE/DEBIAN"
cat > "$STAGE/DEBIAN/control" <<EOF
Package: ghidra-termux
Version: ${VERSION}
Architecture: ${ARCH}
Maintainer: bbaobaob <bbaobaob@users.noreply.github.com>
Installed-Size: ${INSTALLED_SIZE}
Depends: openjdk-21, bash, coreutils, unzip, curl
Section: devel
Priority: optional
Homepage: https://github.com/bbaobaob/ghidra-termux
Description: NSA Ghidra 12.1.4 headless reverse-engineering suite for Termux (ARM64)
 Full Ghidra headless analyzer running natively on Android ARM64 via Termux,
 including the ARM64 decompiler binaries that official Ghidra releases do not
 ship (they only provide linux_x86_64/win_x86_64 natives).
 .
 Ships the phone-tuned \`ghidra-termux' launcher: JDK auto-discovery, heap
 auto-sized to 1/4 of device RAM, SerialGC, big.LITTLE thread-pool cap, and
 \$PREFIX/tmp-based temp/cache/settings dirs.
 .
 Usage: ghidra-termux <project-dir> <project-name> -import ./binary \\
          -scriptPath \$PREFIX/share/ghidra-termux/test \\
          -postScript DecompileAll.java out.c
EOF

cat > "$STAGE/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
P=/data/data/com.termux/files/usr
if [ ! -x "$P/lib/jvm/java-21-openjdk/bin/java" ] && [ ! -x "$P/lib/jvm/java-17-openjdk/bin/java" ]; then
    echo "ghidra-termux: JDK not found. Install one with: pkg install openjdk-21"
fi
echo "ghidra-termux 12.1.4 installed."
echo "  launcher : $P/bin/ghidra-termux (alias: ghidra)"
echo "  test/docs: $P/share/ghidra-termux/"
echo "  example  : ghidra-termux ~/proj p -import ./libfoo.so \\"
echo "               -scriptPath $P/share/ghidra-termux/test -postScript DecompileAll.java out.c"
exit 0
EOF
chmod 755 "$STAGE/DEBIAN/postinst"

# md5sums (nice-to-have; some tools expect them)
if command -v md5sum >/dev/null; then
  (cd "$ROOT" && find . -type f -exec md5sum {} \; | sed 's|  \./|  |') > "$STAGE/DEBIAN/md5sums" 2>/dev/null || true
fi

rm -f "$OUT"
dpkg-deb -b "$STAGE" "$OUT" >/dev/null
echo "build-deb: wrote $OUT ($(du -h "$OUT" | cut -f1))"
