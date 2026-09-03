#!/usr/bin/env python3
# 课 12 档案回写 1/2：00-学习档案.md
# 1) 进度表：课 12 三行 ⬜ -> ✅
# 2) 评审记录表：追加课 12 一行
import io, re, sys

P = "/mnt/d/projects/learning/victoriametrics/00-学习档案.md"
src = open(P, encoding="utf-8").read()
orig = src
DATE = "2026-09-02"

# ---------- 1) 进度表 ----------
rows = [
    ("| 5 | 课 12 | 快照与备份恢复 | ⬜ 未开始 | - | - |",
     f"| 5 | 课 12 | 快照与备份恢复 | ✅ 已完成 | {DATE} | 见讲义 |"),
    ("| 5 | 课 12 | 迁移路径 | ⬜ 未开始 | - | - |",
     f"| 5 | 课 12 | 迁移路径 | ✅ 已完成 | {DATE} | 见讲义 |"),
    ("| 5 | 课 12 | 选型决策：什么时候不该用 VM | ⬜ 未开始 | - | - |",
     f"| 5 | 课 12 | 选型决策：什么时候不该用 VM | ✅ 已完成 | {DATE} | 见讲义 |"),
]
for old, new in rows:
    if old in src:
        src = src.replace(old, new, 1)
        print(f"  [OK] 进度表：{old.split('|')[3].strip()}")
    elif new in src:
        print(f"  [SKIP] 已是完成态：{new.split('|')[3].strip()}")
    else:
        print(f"  [WARN] 未找到：{old}")
        sys.exit(1)

# ---------- 2) 评审记录 ----------
REC = (
    f"| {DATE} | 课 12《备份恢复、迁移与选型决策》 | 主 agent 内联（pedagogy + learner） | "
    "**P0×0 / P1×2（均已修复）**。核心产出：① **快照是硬链接的冻结视图**——快照文件与原始文件 "
    "同一 inode（`inode=7318349394894097`）、`links=3`，建快照 `df` 仅增 **184 KB**，"
    "写入 300 条后快照 md5 不变（`7dea362b…`）证明是冻结视图；② **vmbackup 拒绝无快照备份**"
    "（`-origin cannot be empty when -snapshotName and -snapshot.createURL aren't set`），"
    "这是设计非缺陷；③ **增量备份效果显著**：首次 7,169,266 B，第二次仅 **136,362 B（1.9%）**；"
    "④ **备份不阻塞在线服务**：备份进行中 20 次写入全成功（316 ms）、查询 0.0397s、`/health` 200；"
    "⑤ **恢复验证完整**：41,774 条序列、618 个指标名与源端完全一致，两批 marker 各 50 条、"
    "抽查 `i=\"7\"` 值均为 7；⑥ **S3/MinIO 全链路打通**（175 对象 / 6.9 MiB / 恢复后 41,794 条），"
    "并踩出路径坑：`-dst=s3://<bucket>/<path>` 与 `-customS3Endpoint` 必须分离，"
    "写成 `s3://http://ip:9000/bucket` 报 `InvalidBucketName`；"
    "⑦ **9p 文件系统不支持 fallocate**（本环境 Windows + WSL 特有坑）："
    "在 `D:\\` 挂载目录恢复报 `cannot fallocate 210 bytes: operation not supported`，"
    "改用 docker 命名卷（overlay）后成功；⑧ **vmctl 迁移实测**：1058 万样本 / 195.4 MB / **5.76 秒**，"
    "指标名 619→646；并踩三个参数坑：必须加 `-s --disable-progress-bar`（否则 "
    "`inappropriate ioctl for device`）、`--remote-read-step-interval` 取值是 "
    "`month/week/day/hour/minute` 而非秒数、vmctl 会对 `--vm-addr` 拼 `/health` 探测"
    "（集群须指向 vmselect 而非 vminsert，后者返回 400）；⑨ **迁移幂等**：同样窗口重跑样本数"
    "完全一致（10,580,035），可安全重跑；⑩ **删除是墓碑机制而非回收**（本课最重要发现）："
    "`/api/v1/admin/tsdb/delete_series` 返 204 且日志确认 `Deleted 20000 series`，"
    "但删 5 万条后磁盘**反增 2,348 KB**、`/series/count` 不降（142,394→142,396），"
    "等 60 秒仍高于删除前 148 KB——**不可逆且无回收站**，本课误删的 20,000 条因备份晚于删除"
    "而**无法找回**，这是「没恢复过的备份等于没备份」的真实教训；"
    "⑪ **时间戳单位陷阱**：import API 用毫秒，传秒级 `1788355138` 会被解析成 **1970-01-22**，"
    "永远查不到；验证写入须用 `/api/v1/export` 而非 `/api/v1/query`（后者有秒级延迟）；"
    "⑫ **RTO/RPO 实测**：完整灾难演练 RTO = **2,548 ms**（纯 vmrestore 1,126 ms），"
    "灾后写入的 500 条全部丢失——RPO 由备份频率决定。"
    "**P1×2 已修**：Agent A 报 Mermaid 图缺失（补备份全链路图）、"
    "Agent B 报 L24 危险命令无安全提示（补⚠️引述说明）。"
    "**遗留未闭环×3**：快照长期保留对空间回收的定量影响、vm-native 跨租户迁移未跑通、"
    "删除后后台合并触发回收的确切时机 | 通过；P1 已落实 |"
)

anchor = "| 2026-09-02 | 课 11《vmagent 与 vmalert》 |"
if REC.split("|")[2].strip() not in src:
    idx = src.find(anchor)
    if idx == -1:
        print("  [FAIL] 未找到课 11 评审记录锚点"); sys.exit(1)
    # 找到课 11 那一行的行尾
    end = src.find("\n", idx)
    src = src[:end + 1] + REC + "\n" + src[end + 1:]
    print("  [OK] 评审记录：课 12 一行已追加")
else:
    print("  [SKIP] 评审记录已存在")

open(P, "w", encoding="utf-8").write(src)
print(f"\n写入完成：{P}")
print(f"  字符数 {len(orig)} -> {len(src)}  (+{len(src)-len(orig)})")
