# Benchmarks — ghidra-termux trên thiết bị thật

> Đo trên: **Samsung Galaxy A06 (SM-A065F)** · Android 16 · 8 nhân · 3.7 GB RAM · Termux · JDK 21.0.12 (openjdk-21) · Ghidra 12.1.4 headless
>
> Phương pháp: `test/bench.sh` — binary mẫu ~200 hàm (switch/loop/string), import + auto-analysis đầy đủ,
> mỗi cấu hình chạy sau một warmup (compile SLEIGH spec cache). Thời gian = wall clock của toàn bộ
> một tiến trình `analyzeHeadless` (gồm JVM startup).

## Kết quả

| Cấu hình | Thời gian | Ghi chú |
|---|---|---|
| Warmup (lần đầu, compile SLEIGH) | — | bị loại khỏi so sánh |
| `GHIDRA_TERMUX_CORES=4` (mặc định) | — | |
| `GHIDRA_TERMUX_CORES=8` | — | |
| SerialGC (mặc định wrapper) | — | |
| G1GC | — | |
| Batch 5 binary / 1 JVM | — | |
| 5 lần chạy riêng lẻ | — | overhead JVM startup mỗi lần |

## Nhận định

<!-- fill after measuring -->

## Vì sao "nhanh hơn"

1. **Decompiler ARM64 native** — bản gốc không chạy được trên Android (không có native `linux_arm_64`);
   không có native thì buộc phải x86-emulation (qemu, chậm ~5-10x) hoặc mất hẳn decompilation.
2. **Heap auto-size = RAM/4** — tránh OOM/LMK kill giữa chừng, tránh phải chạy lại từ đầu.
3. **SerialGC** — overhead bộ nhớ thấp nhất trên Android (ZGC/Shenandoah không build cho ARM).
4. **`cpu.core.override`** — không trải thread pool ra nhân efficiency (big.LITTLE).
5. **SLEIGH prewarm** — `.sla` cache compile sẵn lúc cài đặt.
6. **Batch import** — một JVM cho nhiều binary thay vì trả tiền startup mỗi file.
