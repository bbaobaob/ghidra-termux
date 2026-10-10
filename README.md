# ghidra-termux

**Ghidra 12.1.4 headless chạy native trên Termux (Android ARM64)** — đầy đủ chức năng phân tích/dịch ngược, decompiler ARM64 biên dịch native, và bộ tối ưu JVM riêng cho điện thoại.

Bản Ghidra chính thức chỉ ship binary native cho `linux_x86_64`/`win_x86_64`. Repo này đóng gói lại Ghidra 12.1.4 + bộ native `linux_arm_64` (decompiler `decompile` + `sleigh`) để chạy trực tiếp trong Termux, không cần root, không cần proot.

## Tính năng

- **Đầy đủ chức năng headless**: import ELF/PE/Mach-O/raw, auto-analysis, disassembly, decompilation, scripting (Java/Jython), FunctionID, string/xref analysis, BSim, export...
- **Decompiler ARM64 native** — biên dịch từ source C++ của Ghidra (cross-build CI trên `ubuntu-24.04-arm`, hoặc build on-device bằng clang). Không dùng qemu/x86 emulation nên tốc độ là native thật.
- **Tối ưu cho điện thoại**:
  - heap tự động = 1/4 RAM thiết bị (clamp 768M–2G, override bằng `GHIDRA_HEADLESS_MAXMEM`)
  - `-XX:+UseSerialGC` — overhead bộ nhớ thấp nhất trên Android (ZGC/Shenandoah không build cho ARM trong Termux)
  - `-Dcpu.core.override` giới hạn thread pool cho đúng nhân big (big.LITTLE)
  - temp/cache/settings dir trỏ về `$PREFIX/tmp` (Termux không có `/tmp`)
  - SLEIGH cache pre-warm lúc cài đặt → lần phân tích đầu không bị chậm do compile `.slaspec`
- **Cài đặt 1 lệnh**, không root.

## Yêu cầu

- Termux (Android, arm64-v8a)
- `openjdk-21` (Ghidra 12.x yêu cầu JDK 21), `unzip`, `curl` hoặc `wget`, `bash`, `coreutils`
- ≥ 2 GB RAM khả dụng, ≥ 2 GB dung lượng trống
- Khuyến nghị: chạy trong `tmux` + `termux-wake-lock` để Android không kill JVM khi phân tích dài

## Cài đặt

```bash
curl -fsSL -o install.sh \
  https://raw.githubusercontent.com/bbaobaob/ghidra-termux/main/install.sh
bash install.sh
```

Hoặc clone repo rồi chạy:

```bash
git clone https://github.com/bbaobaob/ghidra-termux.git
cd ghidra-termux
bash install.sh                 # dùng native build sẵn từ GitHub Releases
# bash install.sh --build-natives   # hoặc tự build decompiler trên máy (~10 phút)
```

Script sẽ: cài dependency → tải zip Ghidra chính thức (verify SHA-256) → giải nén vào `$PREFIX/opt/ghidra-termux` → tải native ARM64 → patch shebang/path cho Termux → cài launcher `ghidra-termux` vào `$PREFIX/bin`.

## Sử dụng

```bash
# import + analyze + decompile mọi function ra C, một lệnh
ghidra-termux ~/proj myproj -import ./libfoo.so \
  -scriptPath ~/ghidra-termux/test -postScript DecompileAll.java out.c

# chỉ định processor (bỏ qua auto-detect)
ghidra-termux ~/proj myproj -import ./firmware.bin \
  -processor AARCH64:LE:64:default -loader BinaryLoader

# batch: import cả thư mục, đệ quy, trong MỘT tiến trình (nhanh hơn gọi lẻ)
ghidra-termux ~/proj myproj -import ./samples -recursive \
  -analysisTimeoutPerFile 300

# pass 2: decompile lại không cần analyze lại
ghidra-termux ~/proj myproj -process libfoo.so -noanalysis \
  -scriptPath ~/ghidra-termux/test -postScript DecompileAll.java out.c

# script postScript tùy chỉnh + export
ghidra-termux ~/proj myproj -import ./target \
  -scriptPath "\$GHIDRA_HOME/Ghidra/Features/Base/ghidra_scripts;~/myscripts" \
  -postScript ExportAll.java ~/export.xml
```

Toàn bộ cờ của `analyzeHeadless` gốc đều dùng được — `ghidra-termux` chỉ thêm lớp tối ưu môi trường rồi `exec` vào `support/analyzeHeadless`.

### Biến môi trường

| Biến | Mặc định | Ý nghĩa |
|---|---|---|
| `GHIDRA_TERMUX_HOME` | `$PREFIX/opt/ghidra-termux` | Đường dẫn cài Ghidra |
| `GHIDRA_HEADLESS_MAXMEM` | RAM/4 (768M–2G) | Heap JVM |
| `GHIDRA_TERMUX_CORES` | `4` | Số core Ghidra dùng cho thread pool |
| `GHIDRA_JAVA_OPTIONS` | — | Cờ JVM thêm (ghidra-termux tự thêm SerialGC, tmpdir...) |
| `JAVA_HOME` | tự tìm `java-2x-openjdk` | JDK 21 |

Ví dụ máy 8 GB RAM, muốn heap lớn hơn và dùng hết nhân:

```bash
GHIDRA_HEADLESS_MAXMEM=3G GHIDRA_TERMUX_CORES=8 ghidra-termux ~/proj p -import ./big.elf
```

## Kiểm tra port

```bash
cd ~/ghidra-termux/test && bash run-test.sh
```

Build 1 binary ARM64 mẫu → import + analyze + decompile headless → kiểm tra output C chứa đúng function (`factorial`, `classify`...) và đo thời gian pass 2.

## Hiệu năng

Xem [docs/BENCHMARKS.md](docs/BENCHMARKS.md) — số đo thực tế trên thiết bị ARM64 (so sánh GC, số core, batch vs lẻ).

## Giới hạn đã biết

- **7-Zip-JBinding**: Ghidra chỉ ship native amd64 cho lib 7z → không import được archive `.7z`/một số firmware. Giải nén trước rồi import file bên trong.
- **Z3 symbolic p-code emulation** (`SymbolicSummaryZ3`): NSA không build cho Linux ARM64. Các tính năng còn lại của decompiler/analysis đầy đủ.
- **GUI** (`ghidraRun`): bản này là headless. Chạy GUI cần thêm termux-x11/VNC và chưa được test.
- **PyGhidra**: chạy được nếu cài `python` + `jpype` trong Termux, nhưng chưa test kỹ — khuyến nghị dùng Java/Jython script.
- **Debugger native (LLDB SWIG)**: không build được cho Linux ARM64.

## Native ARM64 được build thế nào?

Ghidra chính thức **không** phát hành native `linux_arm_64` (xem [ghidra#3622](https://github.com/NationalSecurityAgency/ghidra/issues/3622), [ghidra#7958](https://github.com/NationalSecurityAgency/ghidra/issues/7958)). Repo này build chúng 2 đường:

1. **CI** (`.github/workflows/build-natives.yml`): `gradle buildNatives_linux_arm_64` trên runner `ubuntu-24.04-arm` (có fallback Makefile `ARCH_TYPE= EXTRA=`), publish lên tag `natives-v12.1.4`.
2. **On-device** (`scripts/build-natives.sh`): `make ghidra_opt sleigh_opt ARCH_TYPE= EXTRA=` bằng clang Termux — 115 file C++, ~5–15 phút. (`EXTRA=` loại 3 file phụ thuộc binutils/BFD — cần `bfd.h` Termux không có — gradle build cũng không dùng chúng.)

Cả hai đều chỉ dùng source C++ ship sẵn trong zip Ghidra chính thức (parser generated `slghparse.cc`/`slghscan.cc` đã có sẵn, không cần flex/bison).

## Credits

- [NSA Ghidra](https://github.com/NationalSecurityAgency/ghidra) — Apache 2.0
- Công thức cross-build ARM64 tham khảo [Jean7z/ghidra-linux-arm64-build](https://github.com/Jean7z/ghidra-linux-arm64-build)

## License

Script/patch trong repo: Apache 2.0 (giống Ghidra). Ghidra bản thân là sản phẩm của NSA, Apache 2.0 — xem `LICENSE`.

> Chỉ dùng cho phân tích mã của bạn hoặc các mục tiêu bạn được phép. Reverse engineering phần mềm không thuộc bạn có thể vi phạm pháp luật/điều khoản dịch vụ.

## English

**ghidra-termux** runs NSA Ghidra 12.1.4 headless natively on Android ARM64 via Termux. Official Ghidra ships no `linux_arm_64` natives, so this repo supplies them (CI cross-build + on-device Makefile build) and wraps `analyzeHeadless` with phone-friendly JVM tuning (auto heap, SerialGC, core cap, `$PREFIX/tmp` dirs). Full analysis/decompilation functionality, no root. Install: `bash install.sh` (see above). Docs in Vietnamese; the scripts are commented in English.
