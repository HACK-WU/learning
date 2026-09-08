#!/usr/bin/env bash
python3 - <<'PY'
# LABELS|VAL_LEN|numSeries|numLabelPairs|mem_MiB|min|max
rows=[(1,12,50005,50008,118.01),(3,12,50005,150008,135.96),
      (5,12,50005,250008,157.52),(1,48,50005,50008,114.77),
      (3,48,50005,150008,179.07)]
NS=50005
print("=== 固定 5 万序列：标签个数的影响（值长=12）===")
base=[r for r in rows if r[0]==1 and r[1]==12][0]
for L,V,ns,nlp,m in rows:
    if V!=12: continue
    print(f"  {L} 标签: numLabelPairs={nlp:>7}  内存={m:7.2f} MiB  Δ相对1标签={m-base[4]:+7.2f} MiB")
d13=[r for r in rows if r[0]==3 and r[1]==12][0]
d15=[r for r in rows if r[0]==5 and r[1]==12][0]
print(f"  → 每增加 1 个标签(5万序列): {(d15[4]-base[4])/4:.2f} MiB  "
      f"= {(d15[4]-base[4])/4*1024/NS:.3f} KiB/序列/标签")
print(f"  → 每增加 1 个标签，numLabelPairs 增加 {NS}（=序列数）")

print()
print("=== 标签值长度的影响（固定序列数与标签数）===")
a=[r for r in rows if r[0]==1 and r[1]==12][0]
b=[r for r in rows if r[0]==1 and r[1]==48][0]
print(f"  1 标签: 12字符={a[4]:.2f} MiB, 48字符={b[4]:.2f} MiB, 差={b[4]-a[4]:+.2f} MiB")
c=[r for r in rows if r[0]==3 and r[1]==12][0]
d=[r for r in rows if r[0]==3 and r[1]==48][0]
print(f"  3 标签: 12字符={c[4]:.2f} MiB, 48字符={d[4]:.2f} MiB, 差={d[4]-c[4]:+.2f} MiB")
print(f"  → 值长 12→48 (4倍) 在 1 标签下影响 {b[4]-a[4]:+.2f} MiB（噪声量级）")
print(f"  → 值长 12→48 (4倍) 在 3 标签下影响 {d[4]-c[4]:+.2f} MiB（显著：标签越多，值长影响被放大）")

print()
print("=== 与业界经验值的对比 ===")
mem_1label = a[4]
per_mil_1label = (mem_1label-29.10)/NS*1000000 + 0
print(f"  本例 1 标签: 100 万序列 ≈ {(mem_1label-29.10)/NS*1000000+29.10:.0f} MiB = {((mem_1label-29.10)/NS*1000000+29.10)/1024:.2f} GiB")
mem_3label = c[4]
print(f"  本例 3 标签: 100 万序列 ≈ {(mem_3label-29.10)/NS*1000000+29.10:.0f} MiB = {((mem_3label-29.10)/NS*1000000+29.10)/1024:.2f} GiB")
mem_5label = d15[4]
print(f"  本例 5 标签: 100 万序列 ≈ {(mem_5label-29.10)/NS*1000000+29.10:.0f} MiB = {((mem_5label-29.10)/NS*1000000+29.10)/1024:.2f} GiB")
print()
print("  业界常见经验值: 100 万序列 ≈ 4~8 GiB")
print("  差异来源: 经验值通常按生产典型标签数(每个序列 10~20 个 label pair)估算，")
print("            且包含查询/规则评估/compaction 的额外开销，本例只测了稳态抓取后的 head。")
PY
