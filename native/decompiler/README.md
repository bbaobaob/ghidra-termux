# native/decompiler — Ghidra decompiler C++ source (ARM64 build input)

Verbatim copy of `Ghidra/Features/Decompiler/src/decompile/{cpp,zlib}` from the
**official Ghidra 12.1.4 release zip** (`ghidra_12.1.4_PUBLIC_20260921.zip`,
SHA-256 `ddac49f9…d4db`).

This is the exact source that the `decompile` and `sleigh` binaries in the
[natives release](../../releases/tag/natives-v12.1.4) were compiled from, so
the shipped binaries are auditable without downloading the 569 MB zip.

- License: Apache-2.0, © National Security Agency (see `LICENSE` in the Ghidra
  release and the repo root).
- The bison/flex-generated parser sources (`xml.cc`, `pcodeparse.cc`,
  `slghparse.cc`, `slghscan.cc`) ship in the release zip and are included here,
  so building needs no flex/bison.
- `zlib/` is the bundled zlib used by the upstream gradle build; the Makefile
  route links the system `-lz` instead (Termux ships zlib).

## Build

```bash
# from this vendored copy (no Ghidra install needed for the compile step):
bash scripts/build-natives.sh native/decompiler/cpp

# or from a Ghidra install tree (default):
bash scripts/build-natives.sh
```

The build runs `make ghidra_opt sleigh_opt ARCH_TYPE= EXTRA=` with Termux clang
(see `scripts/build-natives.sh` for the `ARCH_TYPE=`/`EXTRA=` rationale and the
libc++ skew fallback), then installs the two binaries into
`<ghidra>/Ghidra/Features/Decompiler/os/linux_arm_64/`.

CI does the same thing inside an `ubuntu-24.04-arm` runner + aarch64 Termux
container (see `.github/workflows/build.yml`) — the result must link against
Android **bionic**; a glibc cross-build will not run on a device.
