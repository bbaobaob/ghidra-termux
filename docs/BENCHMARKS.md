# Benchmarks — ghidra-termux trên thiết bị thật

> Đo trên: **Samsung Galaxy A06 (SM-A065F)** · Android 16 · 8 nhân (2×A75 + 6×A55) · 3.7 GB RAM · Termux · JDK 21.0.12 (openjdk-21) · Ghidra 12.1.4 headless · native decompiler ARM64
>
> Phương pháp: binary mẫu ~200 hàm (switch/loop/string, 37 KB), import + auto-analysis đầy đủ + decompile toàn bộ function qua postScript. Mỗi cấu hình chạy sau cooldown (điện thoại budget throttle nhiệt nhanh — không cooldown thì số sau bị nhiễu tới ~5×). "cpu" = user+sys của `time`.

## Kết quả (thiết bị mát, có cooldown)

| Cấu hình | Wall | CPU (u+s) | Decompiled | Ghi chú |
|---|---|---|---|---|
| **Default** (SerialGC, cores=4) | **37.6 s** | 66.5 s | 23/23 | cấu hình wrapper mặc định |
| G1GC | 44.4 s | 69.0 s | 23/23 | chậm hơn SerialGC ~18% wall |
| cores=2 | 39.7 s | 71.3 s | 23/23 | ≈ cores=4 (SoC chỉ có 2 nhân big) |
| cores=8 | **1257 s** | — | — | đo ở session ấm (cùng session với cores=4=170s → tỷ lệ 7.4×); budget phone với 6 nhân A55 kéo cả thread pool |
| **Batch 5 binary / 1 JVM** | **102.7 s** | 133.3 s | 23/binary | ~20.5 s/binary |
| 5 lần chạy riêng lẻ | 286.4 s (tổng) | — | 23 mỗi lần | ~57 s/binary |

## Nhận định

1. **cores=4 (mặc định) là quyết định đúng.** Trên SoC 2-big/6-little, để Ghidra trải thread pool ra 8 nhân làm thời gian phân tích tăng **7–30×** (các phase song song bị gate bởi nhân chậm nhất). cores=2 ≈ cores=4; cả hai đều xa nhanh hơn cores=8.
2. **Batch import nhanh 2.8×** so với gọi `analyzeHeadless` cho từng file — một lần trả chi phí JVM startup (~30 s cho 200 jar + init).
3. **SerialGC thắng G1GC** cả wall lẫn CPU trên thiết bị 3.7 GB, và overhead bộ nhớ thấp hơn (quan trọng với Android LMK). ZGC/Shenandoah không build cho ARM trong Termux nên không phải lựa chọn.
4. Lần chạy đầu tiên sau cài đặt (cold page cache) ~58 s; các lần sau ~32–38 s.

## Vì sao "nhanh hơn" (so với chạy Ghidra trên Android theo cách khác)

1. **Decompiler ARM64 native** — bản gốc không ship native `linux_arm_64` nên không decompile được; cách chạy khác (x86-emulation) chậm nhiều lần hoặc mất hẳn tính năng.
2. **Heap auto-size = RAM/4** — tránh OOM/LMK kill giữa chừng, khỏi chạy lại từ đầu.
3. **`cpu.core.override=4`** — không trải thread pool ra nhân efficiency (xem số liệu cores=8 ở trên).
4. **SerialGC** — overhead bộ nhớ thấp nhất.
5. **Batch import** — một JVM cho nhiều binary.
6. Ghidra 12.1.4 + JDK 21 mới nhất.
