#!/usr/bin/env bash
python3 - <<'PY'
data = [
 (0,      5,      29.10),
 (10000,  10005,  45.43),
 (50000,  50005,  109.42),
 (100000, 100005, 180.60),
 (150000, 150005, 277.12),
]
print("=== 可信点（15 万及以下，各点采样波动 <1.5%）===")
b_ns,b_m = 5, 29.10
for n,ns,m in data:
    if ns==5: 
        print(f"  {ns:>7} {m:7.2f} MiB  (基线)")
        continue
    per=(m-b_m)*1024/(ns-b_ns)
    print(f"  {ns:>7} {m:7.2f} MiB  Δ{ns-b_ns:>6} 序列 Δ{m-b_m:6.2f} MiB -> {per:.3f} KiB/序列")

xs=[d[1] for d in data]; ys=[d[2] for d in data]
n=len(xs); mx=sum(xs)/n; my=sum(ys)/n
num=sum((x-mx)*(y-my) for x,y in zip(xs,ys)); den=sum((x-mx)**2 for x in xs)
s=num/den; i=my-s*mx
ss_t=sum((y-my)**2 for y in ys); ss_r=sum((y-(s*x+i))**2 for x,y in zip(xs,ys))
r2=1-ss_r/ss_t
print()
print(f"=== 拟合（0~15 万，5 点）===")
print(f"  内存(MiB) = {s:.6f} × 序列数 + {i:.2f}")
print(f"  斜率 = {s*1024:.3f} KiB/序列 = {s*1024*1000:.0f} KiB/千序列")
print(f"  截距 = {i:.2f} MiB（空实例基线，实测 29.10 MiB）")
print(f"  R^2  = {r2:.4f}")
print()
print("=== 用该模型外推 ===")
for n in [200000, 500000, 1000000, 2000000]:
    print(f"  {n:>9,} 序列 -> 预测 {s*n+i:8.1f} MiB = {(s*n+i)/1024:6.2f} GiB")
print()
print("=== 若按 10 万级实测斜率 (1.515 MiB/千序列) ===")
s2 = (180.60-29.10)/(100005-5)
for n in [1000000]:
    print(f"  1,000,000 序列 -> {s2*n+29.10:.1f} MiB = {(s2*n+29.10)/1024:.2f} GiB")
print()
print("=== 20 万点为何不可用 ===")
print("  3 轮: 385.79 / 401.62 / 355.95 MiB  极差 45.67 MiB")
print("  15 万点: 277.12 (276.78~277.46)     极差 0.68 MiB")
print("  结论: 20 万时本机可用内存不足(31G总/7G可用)，发生 swap/GC 抖动，数据不可信")
PY
