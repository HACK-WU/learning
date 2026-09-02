# -*- coding: utf-8 -*-
"""
engine.py —— 阶段 4 体检（L10 存储引擎 / L11 向量化执行 / L12 性能调优）

📌 回指：L10《存储引擎：WAL、Parquet 与压实》、L11《向量化执行》、L12《写入与查询性能调优》

本模块回答三个问题：
  1. 数据量算不算大（容量与成本）
  2. 最关键：能存 ≠ 能查 —— 文件数是否突破可查窗口
  3. 写入批次参数是否踩中双阈值
"""

from config import (
    BATCH_BYTES, BATCH_LINES, COMPRESS_RATIO, CORE_MAX_QUERY_DAYS,
    FILES_PER_DAY, MEM_EXEC_POOL, MEM_FORCE_SNAPSHOT, MEM_PARQUET_CACHE,
    RAW_POINT_BYTES, SKU_FILE_LIMIT, Finding, Workload,
)


def raw_bytes(pps: int, days: float) -> float:
    """压缩前字节数。"""
    return pps * 86_400 * days * RAW_POINT_BYTES


def stored_bytes(pps: int, days: float) -> float:
    """⭐ 压缩后字节数：25x 是假设值，官方口径是 'often 10-100x smaller'。"""
    return raw_bytes(pps, days) * COMPRESS_RATIO


def files_for(days: float) -> float:
    """📌 文件数只跟墙钟有关，跟数据量无关（L16 已验证：砍一半指标一个文件都不少）。"""
    return FILES_PER_DAY * days


def fmt(b: float) -> str:
    for unit in ("B", "KB", "MB", "GB", "TB", "PB"):
        if b < 1024 or unit == "PB":
            return f"{b:,.1f} {unit}"
        b /= 1024.0


def check_capacity(w: Workload) -> list:
    """容量估算 + 内存三默认的隐性代价。"""
    out = []
    raw = raw_bytes(w.pps, w.raw_retention_days)
    stored = stored_bytes(w.pps, w.raw_retention_days)

    out.append(Finding(
        "INFO", "阶段 4 · L10",
        f"容量估算（保留 {w.raw_retention_days} 天）",
        f"压缩前 {fmt(raw)} → 压缩后约 {fmt(stored)}"
        f"（⚠️ 假设 25x 压缩，官方口径 'often 10-100x smaller'，取典型值）",
        "把 RAW_POINT_BYTES 与 COMPRESS_RATIO 换成你自己的实测值",
    ))

    total_mem = MEM_EXEC_POOL + MEM_PARQUET_CACHE + MEM_FORCE_SNAPSHOT
    out.append(Finding(
        "P1", "阶段 4 · L13",
        f"内存三默认相加 = {total_mem:.0%}",
        f"--exec-mem-pool-size {MEM_EXEC_POOL:.0%} + --parquet-mem-cache-size {MEM_PARQUET_CACHE:.0%} "
        f"+ --force-snapshot-mem-size {MEM_FORCE_SNAPSHOT:.0%} = {total_mem:.0%}。"
        "这是「内存比 CPU 先到瓶颈」的根因 —— 4GB 机器只剩 0.4GB 给别的一切。",
        "按官方建议显式调小，不要三个都吃默认值；调之前先确认各自的归属参数",
    ))
    return out


def check_query_window(w: Workload, allowed_skus: list = None) -> list:
    """⭐ 全项目最硬的一条：432 文件上限 → Core 只能查 3 天。

    allowed_skus：由 decision.py 排雷后传下来的幸存 SKU 列表。
    📌 约束归属：Core 若已被排除（如业务要求托管），就不该再报 Core 的 432 约束 ——
       否则会出现「告诉你 Core 不能用，又告诉你 Core 查不到」的自相矛盾。
    """
    out = []
    n_files = files_for(w.query_window_days)

    out.append(Finding(
        "INFO", "阶段 4 · L11",
        f"可查窗口需求 {w.query_window_days} 天 → 需打开 {n_files:,.0f} 个 Parquet 文件",
        f"每 {10} 分钟一个 gen1 Parquet 文件 = 每天 {FILES_PER_DAY} 个，"
        f"文件数只跟墙钟有关、跟数据量无关。",
        "拿这个数字对照下一条",
    ))

    # ⭐ L19 P0-1：按 SKU 分列，432 只对 Core 成立；且只在 Core 仍是候选时才报
    for sku, limit in SKU_FILE_LIMIT.items():
        if limit is None:
            continue
        if allowed_skus is not None and sku not in allowed_skus:
            continue
        if n_files > limit:
            over = n_files / limit
            out.append(Finding(
                "P0", "阶段 4 · L11",
                f"【{sku}】{n_files:,.0f} 文件 > 上限 {limit}（超 {over:.1f} 倍）→ 查询直接报错",
            f"⭐ {limit} 是 query-file-limit 的默认值，{CORE_MAX_QUERY_DAYS:.0f} 天是它的派生值"
            "（L11 已核实：代码里没有任何时间判断，72 小时是 432×10min 换算来的）。"
            "⚠️ 超限的表现是**直接报错**，不是变慢。",
                "三选一：① 缩短查询窗口到 3 天内 ② 用降采样层承接长周期查询 ③ 换有 compactor 的 SKU",
            ))

    managed = [s for s, lim in SKU_FILE_LIMIT.items() if lim is None]
    out.append(Finding(
        "INFO", "阶段 6 · L19",
        f"【{' / '.join(managed)}】有 compactor，不受 432 约束",
        "⚠️ 这些 SKU 的小文件会被持续合并，超过 432 是**性能衰减**而非报错。"
        "这是 L19 的 P0-1 修复点：432 是 Core 的属性，不是 InfluxDB 的属性。",
        "别把 Core 的约束套到别的 SKU 上，也别把别的 SKU 的宽松算到 Core 头上",
    ))

    if (w.query_window_days > CORE_MAX_QUERY_DAYS and w.source_version == "none"
            and (allowed_skus is None or "core" in allowed_skus)):
        out.append(Finding(
            "P1", "阶段 6 · L19",
            f"查询窗口 {w.query_window_days} 天 > Core 天然可查 {CORE_MAX_QUERY_DAYS:.0f} 天，但没配降采样",
            "默认形态下这 {:.0f} 天里只有最近 3 天查得到 —— 超出的部分本质只是冷备份。".format(
                w.query_window_days),
            "配降采样层（见 retention.py），或直接选有 compactor 的 SKU",
        ))
    return out


def check_write_path(w: Workload) -> list:
    """⭐ L12：批量写入双阈值 10,000 行或 10 MB，谁先到算谁。"""
    out = []
    bytes_per_line = RAW_POINT_BYTES
    lines_to_10mb = BATCH_BYTES // bytes_per_line

    if lines_to_10mb > BATCH_LINES:
        verdict = f"按典型行长 {bytes_per_line} 字节，凑满 10 MB 需要 {lines_to_10mb:,} 行 > {BATCH_LINES:,} 行 → **行数先到**"
        binding = "行数"
    else:
        verdict = f"行长 {bytes_per_line} 字节时 {lines_to_10mb:,} 行即达 10 MB < {BATCH_LINES:,} 行 → **字节数先到**"
        binding = "字节数"

    out.append(Finding(
        "INFO", "阶段 4 · L12",
        f"批量阈值：{verdict}",
        f"⭐ 官方原文 '10,000 lines of line protocol or 10 MBs, whichever threshold is met first'。"
        f"⚠️ 客户端库默认 batch_size=1000，比官方推荐保守 10 倍。",
        f"按{binding}调 batch_size / flush_interval；先算你自己的平均行长再定",
    ))

    out.append(Finding(
        "P2", "阶段 4 · L12",
        "10 MB 与 --max-http-request-size 默认 10mb 撞车",
        "⚠️ 官方未明示这个 10mb 指的是压缩前还是压缩后。若按压缩前算，"
        "一个刚好 10 MB 的批次会在 HTTP 层被拒。",
        "取保守策略：批次控制在 8 MB 以内，或显式调大 --max-http-request-size",
    ))
    return out


def run(w: Workload, allowed_skus: list = None) -> list:
    return (check_capacity(w) + check_query_window(w, allowed_skus)
            + check_write_path(w))
