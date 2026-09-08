#!/usr/bin/env bash
python3 - <<'PY'
N=50005; SAMPLES=29; TOTAL=10  # MiB
per_sample = TOTAL*1024/(N*SAMPLES)
print("=== 磁盘成本（实测：5万序列 × 29 样本 = 145万样本）===")
print(f"  总磁盘 = {TOTAL} MiB（其中 WAL 10 MiB，chunks_head <1 MiB）")
print(f"  每样本 ≈ {per_sample:.4f} KiB = {per_sample*1024:.1f} 字节")
print(f"  每序列每天(30s间隔, 2880样本) ≈ {per_sample*2880/1024:.2f} MiB")
print(f"  每序列每天(15s间隔, 5760样本) ≈ {per_sample*5760/1024:.2f} MiB")
print()
print("=== 由此估算 100 万序列 × 15 天保留 ===")
for interval,name in [(15,"15s"),(30,"30s")]:
    spd = 86400//interval
    mib = per_sample*spd*15/1024
    print(f"  {name} 间隔: 每序列15天 {mib:.2f} MiB -> 100万序列 {mib*1000000/1024/1024:.2f} TiB")
print()
print("⚠️  注意：这是**未 compaction 的 WAL 口径**，落 block 后经压缩通常显著更小。")
print("    真实生产需以 compaction 后的 block 为准（见下一步实测）。")
PY
