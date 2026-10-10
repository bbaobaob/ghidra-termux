#!/usr/bin/env bash
# install.sh -- install Ghidra 12.1.4 (headless) for Termux / Android ARM64.
#
# What it does:
#   1. checks/installs Termux dependencies (openjdk-21, unzip, curl/wget)
#   2. downloads the official Ghidra release zip and verifies its SHA-256
#   3. installs it to $PREFIX/opt/ghidra-termux
#   4. fetches the ARM64 native decompiler (decompile+sleigh) from this repo's
#      GitHub release (or builds them on-device with --build-natives)
#   5. patches shebangs/paths for Termux (scripts/patch-termux.sh)
#   6. installs the `ghidra-termux` launcher into $PREFIX/bin
#
# Usage:
#   bash install.sh                 # standard install (prebuilt natives)
#   bash install.sh --build-natives # compile decompiler on-device instead
#   bash install.sh --no-prewarm    # skip SLEIGH cache warm-up
#
# No root required.

set -euo pipefail

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
OPT_DIR="$PREFIX/opt"
INSTALL_DIR="$OPT_DIR/ghidra-termux"
BIN_DIR="$PREFIX/bin"
CACHE_DIR="${GHIDRA_TERMUX_CACHE:-$HOME/.cache/ghidra-termux}"

GHIDRA_VERSION="12.1.4"
GHIDRA_BUILD="20260921"
GHIDRA_ZIP="ghidra_${GHIDRA_VERSION}_PUBLIC_${GHIDRA_BUILD}.zip"
GHIDRA_URL="https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_${GHIDRA_VERSION}_build/${GHIDRA_ZIP}"
GHIDRA_SHA256="ddac49f903da9d5bac833e5cc79395098b9c33cfd3279be5f31bd00387d2d4db"

REPO="bbaobaob/ghidra-termux"
NATIVES_TAG="natives-v${GHIDRA_VERSION}"
NATIVES_ASSET="ghidra-natives-android-aarch64-${GHIDRA_VERSION}.tar.gz"

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

BUILD_NATIVES=0
PREWARM=1

while [ $# -gt 0 ]; do
  case "$1" in
    --build-natives) BUILD_NATIVES=1 ;;
    --no-prewarm)    PREWARM=0 ;;
    -h|--help)
      sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "install: unknown option '$1'" >&2; exit 1 ;;
  esac
  shift
done

log() { echo "==> $*"; }
die() { echo "install: $*" >&2; exit 1; }

# ---------------------------------------------------------------- deps -------
log "checking dependencies"
MISSING=""
command -v bash    >/dev/null || MISSING="$MISSING bash"
command -v readlink >/dev/null || MISSING="$MISSING coreutils"
command -v unzip   >/dev/null || MISSING="$MISSING unzip"
command -v curl    >/dev/null || command -v wget >/dev/null || MISSING="$MISSING curl"
[ -x "$PREFIX/lib/jvm/java-21-openjdk/bin/java" ] || [ -x "$PREFIX/lib/jvm/java-17-openjdk/bin/java" ] \
  || MISSING="$MISSING openjdk-21"
if [ -n "$MISSING" ]; then
  log "missing packages:$MISSING -- installing"
  pkg install -y $MISSING || die "pkg install failed; install manually: pkg install$MISSING"
fi

# --------------------------------------------------------------- download ----
mkdir -p "$CACHE_DIR"
ZIP="$CACHE_DIR/$GHIDRA_ZIP"
if [ ! -f "$ZIP" ]; then
  log "downloading Ghidra $GHIDRA_VERSION (~570 MB, this takes a while)"
  if command -v curl >/dev/null; then
    curl -fL --retry 3 -C - -o "$ZIP.part" "$GHIDRA_URL" || die "download failed"
  else
    wget -c -q -O "$ZIP.part" "$GHIDRA_URL" || die "download failed"
  fi
  mv "$ZIP.part" "$ZIP"
else
  log "using cached $ZIP"
fi

log "verifying SHA-256"
echo "$GHIDRA_SHA256  $ZIP" | sha256sum -c - || die "checksum mismatch; delete $ZIP and retry"

# ---------------------------------------------------------------- install ----
log "installing to $INSTALL_DIR"
rm -rf "$INSTALL_DIR"
mkdir -p "$OPT_DIR"
unzip -q "$ZIP" -d "$OPT_DIR"
mv "$OPT_DIR/ghidra_${GHIDRA_VERSION}_PUBLIC" "$INSTALL_DIR"

# ---------------------------------------------------------------- natives ----
if [ "$BUILD_NATIVES" = "1" ]; then
  log "building ARM64 natives on-device (slow)"
  bash "$SCRIPT_DIR/scripts/build-natives.sh"
else
  log "fetching prebuilt ARM64 natives ($NATIVES_ASSET from $REPO)"
  if command -v gh >/dev/null && gh release download "$NATIVES_TAG" --repo "$REPO" \
       --pattern "$NATIVES_ASSET" --dir "$CACHE_DIR" --clobber 2>/dev/null; then
    tar -xzf "$CACHE_DIR/$NATIVES_ASSET" -C "$INSTALL_DIR"
    log "natives installed"
  else
    echo "install: WARNING: could not download prebuilt natives." >&2
    echo "install: decompilation will not work until you run:" >&2
    echo "install:   bash $SCRIPT_DIR/scripts/build-natives.sh" >&2
  fi
fi

# ----------------------------------------------------------------- patch -----
log "patching for Termux"
bash "$SCRIPT_DIR/scripts/patch-termux.sh" "$INSTALL_DIR"

# --------------------------------------------------------------- launcher ----
log "installing launcher to $BIN_DIR/ghidra-termux"
install -m 755 "$SCRIPT_DIR/scripts/ghidra-termux" "$BIN_DIR/ghidra-termux"
ln -sf ghidra-termux "$BIN_DIR/ghidra"

# --------------------------------------------------------------- prewarm -----
# First use of a processor spec compiles SLEIGH .slaspec -> .sla (slow). Warming
# the cache at install time keeps the first real analysis fast.
if [ "$PREWARM" = "1" ]; then
  log "warming SLEIGH cache (first import compiles processor specs)"
  TINY="$(mktemp -d)/warm.c"
  printf 'int main(){return 0;}\n' > "$TINY"
  if command -v gcc >/dev/null || command -v clang >/dev/null; then
    BIN="$(mktemp -d)/warm"
    (gcc -O0 -o "$BIN" "$TINY" 2>/dev/null || clang -O0 -o "$BIN" "$TINY" 2>/dev/null) || true
    if [ -x "$BIN" ]; then
      PDIR="$HOME/.ghidra-termux-prewarm"
      mkdir -p "$PDIR"
      GHIDRA_TERMUX_CORES=2 timeout 600 "$BIN_DIR/ghidra-termux" "$PDIR" warm \
        -import "$BIN" -processor AARCH64:LE:64:v8A -analysisTimeoutPerFile 120 \
        >/dev/null 2>&1 || echo "install: prewarm skipped (non-fatal)"
      rm -rf "$PDIR"
    fi
  fi
fi

# ----------------------------------------------------------------- done ------
cat <<EOF

install: done!

  Ghidra $GHIDRA_VERSION (headless) : $INSTALL_DIR
  launcher                        : $BIN_DIR/ghidra-termux (alias: ghidra)

Try it:
  ghidra-termux ~/proj myproj -import ./some-binary -postScript DecompileAll.java out.c

Docs: https://github.com/$REPO
EOF
