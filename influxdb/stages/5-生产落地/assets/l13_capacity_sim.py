# -*- coding: utf-8 -*-
"""容量规划模拟器 —— 纯标准库，可直接运行
对照 L13 知识点 2：容量规划与硬件

公式：存储量 = 点数/秒 x 86400 x 保留天数 x 每点字节数 x 压缩后比例 x 副本数

⚠️ 假设值说明（抓趋势，不抓绝对值）：
  BYTES_PER_POINT = 120   —— 典型 line protocol 行长，L12 已核实典型点位 60-150 字节
  压缩比三档 10x / 25x / 50x —— 官方博客口径为 "often 10-100x smaller than its raw form"，
                                 这里取区间内的三档做保守/典型/乐观对照
  内存三参数默认值 —— 均取自官方 config-options 原文（exec-mem-pool 20% /
                       parquet-mem-cache 20% / force-snapshot 50%）
"""
import time
import random

random.seed(20260901)

# ---------- 假设参数 ----------
BYTES_PER_POINT = 120          # 每行 line protocol 大致字节数
COMPRESS = [("保守 10x", 0.10), ("典型 25x", 0.04), ("乐观 50x", 0.02)]

# ---------- 官方默认值 ----------
GEN1_MIN = 10                  # gen1-duration 默认 10m，仅 1m/5m/10m 三档
FILES_PER_DAY = 144            # 86400 / (10*60)
QUERY_FILE_LIMIT = 432         # query-file-limit 默认
MEM_EXEC_POOL = 0.20           # --exec-mem-pool-size 默认 20%
MEM_PARQUET_CACHE = 0.20       # --parquet-mem-cache-size 默认 20%
MEM_FORCE_SNAPSHOT = 0.50      # --force-snapshot-mem-size 默认 50%

# ---------- Cloud Serverless 官方单价 ----------
PRICE_IN_PER_MB = 0.0025       # $0.0025 / MB
PRICE_QUERY_PER_100 = 0.012    # $0.012 / 100 executions
PRICE_STORAGE_GB_HOUR = 0.002  # $0.002 / GB-hour
PRICE_OUT_PER_GB = 0.09        # $0.09 / GB


def storage_bytes(pps, days, ratio, replicas=1):
    """点数/秒 x 保留天数 -> 压缩后字节数"""
    return pps * 86400 * days * BYTES_PER_POINT * ratio * replicas


def human(size_bytes):
    """字节数转人类可读"""
    for unit in ("B", "KB", "MB", "GB", "TB", "PB"):
        if size_bytes < 1024 or unit == "PB":
            return "{:,.1f} {}".format(size_bytes, unit)
        size_bytes /= 1024.0


def daily_written(pps, ratio):
    """每天写入的压缩后字节数"""
    return pps * 86400 * BYTES_PER_POINT * ratio


print("=" * 74)
print("实验 A：容量规划模拟器")
print("=" * 74)
print("公式：存储量 = 点数/秒 x 86400 x 保留天数 x 每点字节数 x 压缩后比例 x 副本数")
print("假设：每点 {} 字节（典型 60-150）；压缩比官方口径 'often 10-100x smaller'".format(BYTES_PER_POINT))
print("      内存三参数默认值取自官方 config-options 原文\n")

print("[1] 写入速率 vs 存储量（保留 30 天，单副本）")
print("    {:>14} {:>16} {:>16} {:>16}".format("点数/秒", "保守 10x", "典型 25x", "乐观 50x"))
for pps in (1000, 10000, 100000, 500000, 1000000):
    row = [human(storage_bytes(pps, 30, r)) for _, r in COMPRESS]
    print("    {:>14,} {:>16} {:>16} {:>16}".format(pps, row[0], row[1], row[2]))

print("\n[2] 保留期 vs 存储量（固定 10 万点/秒，单副本）")
print("    {:>10} {:>16} {:>16} {:>16}".format("保留期", "保守 10x", "典型 25x", "乐观 50x"))
for days in (3, 7, 30, 90, 365):
    row = [human(storage_bytes(100000, days, r)) for _, r in COMPRESS]
    mark = ""
    if days > 30:
        mark = "  <- Core 查不了"
    print("    {:>9}天 {:>16} {:>16} {:>16}{}".format(days, row[0], row[1], row[2], mark))

print("\n[3] 保留期 vs Core 的 Parquet 文件数（gen1=10m -> 每天 144 个，上限 432）")
print("    {:>10} {:>14} {:>16} {:>10}".format("保留期", "文件数", "超 432 倍数", "结论"))
for days in (1, 3, 7, 30, 90):
    files = FILES_PER_DAY * days
    over = files / QUERY_FILE_LIMIT
    verdict = "可查" if files <= QUERY_FILE_LIMIT else "超限（报错）"
    print("    {:>9}天 {:>14,} {:>15.1f}x {:>14}".format(days, files, over, verdict))
print("    注：432 x 10min = 4,320 分钟 = 72 小时。数据稀疏时凑不满文件数，故有人能查更久")

print("\n[4] 内存预算分配（官方三个默认百分比之和）")
total_pct = MEM_EXEC_POOL + MEM_PARQUET_CACHE + MEM_FORCE_SNAPSHOT
print("    {:<34} {:>10}".format("--exec-mem-pool-size（查询执行）", "{:.0f}%".format(MEM_EXEC_POOL * 100)))
print("    {:<34} {:>10}".format("--parquet-mem-cache-size（文件缓存）", "{:.0f}%".format(MEM_PARQUET_CACHE * 100)))
print("    {:<34} {:>10}".format("--force-snapshot-mem-size（缓冲阈值）", "{:.0f}%".format(MEM_FORCE_SNAPSHOT * 100)))
print("    {:<34} {:>10}".format("合计", "{:.0f}%".format(total_pct * 100)))
print("\n    ⚠️ 三个默认值相加 = {:.0f}%，意味着默认配置已把几乎全部内存分片完毕。".format(total_pct * 100))
print("       只剩 {:.0f}% 给进程本身、操作系统页缓存与其他开销 —— 这是 Core 上".format((1 - total_pct) * 100))
print("       「内存比 CPU 先到瓶颈」的根因，也是官方调优页把这几项列为首选的原因。\n")
print("    {:>10} {:>14} {:>14} {:>14} {:>10}".format("物理内存", "exec 20%", "cache 20%", "snapshot 50%", "剩余"))
for ram_gb in (4, 8, 16, 32, 64):
    print("    {:>8}GB {:>14} {:>14} {:>14} {:>10}".format(
        ram_gb,
        "{:.1f}GB".format(ram_gb * MEM_EXEC_POOL),
        "{:.1f}GB".format(ram_gb * MEM_PARQUET_CACHE),
        "{:.1f}GB".format(ram_gb * MEM_FORCE_SNAPSHOT),
        "{:.1f}GB".format(ram_gb * (1 - total_pct))))

print("\n[5] Cloud Serverless 月度成本估算（官方单价）")
print("    单价：写入 $0.0025/MB ｜ 查询 $0.012/100次 ｜ 存储 $0.002/GB-hour ｜ 出流量 $0.09/GB")
print("    {:>12} {:>12} {:>14} {:>12} {:>12}".format("日写入(GB)", "月存储(GB)", "存储费", "写入费", "月合计"))
for daily_gb in (1, 10, 50, 100, 500):
    storage_gb = daily_gb * 30
    storage_cost = storage_gb * 24 * 30 * PRICE_STORAGE_GB_HOUR
    write_cost = daily_gb * 1024 * 30 * PRICE_IN_PER_MB
    print("    {:>12,} {:>12,} {:>13,.0f}$ {:>11,.0f}$ {:>11,.0f}$".format(
        daily_gb, storage_gb, storage_cost, write_cost, storage_cost + write_cost))
print("    注：未计查询费与出流量费。查询费按次计（$0.012/100次），")
print("        高频刷新的 Grafana 大屏是查询费的主要来源（见本课误区第 9 条）")

print("\n[6] 副本数对存储量的影响（10 万点/秒，保留 30 天，典型 25x）")
print("    {:>10} {:>16} {:>10}".format("副本数", "存储量", "增量"))
base = storage_bytes(100000, 30, 0.04, 1)
for replicas in (1, 2, 3):
    cur = storage_bytes(100000, 30, 0.04, replicas)
    print("    {:>10} {:>16} {:>10}".format(replicas, human(cur), "{:.0f}x".format(cur / base)))
print("    注：Core 是单机无副本；Enterprise 的 read replica 与对象存储自身冗余是两回事")
print("=" * 74)
