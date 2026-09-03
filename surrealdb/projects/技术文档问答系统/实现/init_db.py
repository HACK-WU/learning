# -*- coding: utf-8 -*-
"""init_db.py —— 建库并灌入种子数据

用法：
    python3 init_db.py

幂等：每次都会先 REMOVE 再重建，可以反复跑。
⚠️ 全程用 root 身份：表级 PERMISSIONS 里 create 是 NONE，记录用户写不进去；
   而 root 完全不受 PERMISSIONS 约束（课 10 实测），所以灌数据必须由 root 做。
"""
import sys
import os
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import Conn, NS, DB, BASE  # noqa: E402
from schema import SCHEMA  # noqa: E402
from seed import build_statements, CORPUS, USERS  # noqa: E402


def split_statements(text):
    """按分号切分 SurrealQL。

    注意：字符串里可能出现分号（本项目的文本语料里有中文分号「；」是安全的，
    但英文分号 ';' 也可能出现在正文里）。这里用简单的引号感知切分。
    """
    out, buf, in_str, esc = [], [], False, False
    for ch in text:
        if esc:
            buf.append(ch)
            esc = False
            continue
        if ch == "\\":
            buf.append(ch)
            esc = True
            continue
        if ch == "'":
            in_str = not in_str
            buf.append(ch)
            continue
        if ch == ";" and not in_str:
            s = "".join(buf).strip()
            if s:
                out.append(s + ";")
            buf = []
            continue
        buf.append(ch)
    tail = "".join(buf).strip()
    if tail:
        out.append(tail)
    return out


def strip_comments(s):
    lines = []
    for ln in s.splitlines():
        st = ln.strip()
        if st.startswith("--"):
            continue
        lines.append(ln)
    return "\n".join(lines)


def run_statements(conn, stmts, label, batch=50, show_errors=5):
    """批量执行语句，精确报告失败位置。

    ⚠️ 为什么要分批：每条语句单独发一次 HTTP，往返约 23ms（课 12 实测基线）。
       6433 条 × 23ms ≈ 148 秒，全是网络开销。合成每批 50 条后降到几秒 —— 这是
       课 12「逐行写与批量写差约 940 倍」结论在项目里的直接应用。

    ⚠️ 为什么仍要检查每条：多语句请求里单条失败不会阻断同批的其他语句
       （课 9 的块级运行器行为），所以必须逐条看响应体里的 status。
    """
    total, ok = len(stmts), 0
    failed = []
    t0 = time.time()
    i = 0
    while i < total:
        chunk = stmts[i:i + batch]
        joined = "\n".join(chunk)
        ok2, payload, err = conn.sql(joined)
        if ok2:
            ok += len(chunk)
        else:
            # 定位批内第几条失败：响应数组下标与语句下标一一对应
            idx_in_batch = 0
            if isinstance(payload, dict):
                # sql() 已把首个 ERR 项作为 payload 返回，需要重新跑一次定位
                for j, s in enumerate(chunk):
                    o3, p3, e3 = conn.sql(s)
                    if not o3:
                        idx_in_batch = j
                        payload, err = p3, e3
                        break
            ok += idx_in_batch
            failed.append((i + idx_in_batch, chunk[idx_in_batch][:100], err,
                           str(payload)[:200]))
            # 从失败的下一条继续，不整批重跑
            i = i + idx_in_batch + 1
            continue
        i += batch
    dt = time.time() - t0

    print("  %s：成功 %d / %d，用时 %.2fs" % (label, ok, total, dt))
    if failed:
        print("  ✗ 失败 %d 条，前 %d 条：" % (len(failed), show_errors))
        for idx, s, err, body in failed[:show_errors]:
            print("    [%d] %s" % (idx, s))
            print("        %s | %s" % (err, body))
    return ok, failed


def main():
    print("=" * 70)
    print("技术文档问答系统 · 初始化")
    print("=" * 70)
    print("目标：%s  NS=%s DB=%s" % (BASE, NS, DB))

    # 建库：先连到 learn 命名空间下的已有库，再创建 docsqa
    boot = Conn(db="learn")
    ok, payload, err = boot.sql("DEFINE DATABASE IF NOT EXISTS %s;" % DB)
    if not ok:
        print("✗ 建库失败：%s %s" % (err, str(payload)[:300]))
        return 1
    print("✓ 数据库 %s 就绪" % DB)

    conn = Conn()

    print()
    print("--- 第 1 步：建表 / 索引 / 权限 / 访问方式 ---")
    stmts = split_statements(strip_comments(SCHEMA))
    print("  schema 语句 %d 条" % len(stmts))
    t0 = time.time()
    n = conn.run_batch(stmts)
    print("  成功 %d / %d，用时 %.2fs" % (n, len(stmts), time.time() - t0))

    print()
    print("--- 第 2 步：灌数据（文档 / 切块 / 倒排 / 引用 / 用户）---")
    data = build_statements()
    print("  数据语句 %d 条（分批发送，每批 50 条）" % len(data))
    ok_count, failed = run_statements(conn, data, "灌数据")
    if failed:
        print("✗ 灌数据存在失败，终止（带着坏数据继续没有意义）")
        return 1

    print()
    print("--- 第 3 步：体检（每条都要有数字，不能只看没报错）---")
    checks = [
        ("doc 条数", "SELECT count() FROM doc GROUP ALL;", len(CORPUS)),
        ("chunk 条数", "SELECT count() FROM chunk GROUP ALL;",
         sum(len(c[4]) for c in CORPUS)),
        ("user 条数", "SELECT count() FROM user GROUP ALL;", len(USERS)),
        ("refs 边数", "SELECT count() FROM refs GROUP ALL;",
         sum(len(c[5]) for c in CORPUS)),
        ("term 条数>0", "SELECT count() FROM term GROUP ALL;", None),
        ("hit 边数>0", "SELECT count() FROM hit GROUP ALL;", None),
    ]
    bad = 0
    for name, q, expect in checks:
        try:
            r = conn.result(q)
            got = r[0]["count"] if isinstance(r, list) and r else r
        except Exception as e:
            print("  ✗ %-14s 查询失败 %s" % (name, str(e)[:120]))
            bad += 1
            continue
        if expect is None:
            okk = got is not None and got > 0
            print("  %s %-14s = %s" % ("✓" if okk else "✗", name, got))
        else:
            okk = got == expect
            print("  %s %-14s = %s (期望 %s)" % ("✓" if okk else "✗", name, got, expect))
        if not okk:
            bad += 1

    print()
    print("--- 第 4 步：索引是否真的可用（EXPLAIN 验证，不能只看定义成功）---")
    vq = "LET $q = %s; SELECT id FROM chunk WHERE emb <|3,40|> $q EXPLAIN;" % (
        "[" + ",".join(["0.5"] * 12) + "]")
    plan = conn.result(vq)
    plan_s = str(plan)
    ok1 = "KnnScan" in plan_s
    print("  %s 向量索引：%s" % ("✓" if ok1 else "✗", "KnnScan" if ok1 else plan_s[:120]))
    if not ok1:
        bad += 1

    fq = "SELECT id FROM chunk WHERE grams @@ '索引' EXPLAIN;"
    plan2 = conn.result(fq)
    plan2_s = str(plan2)
    ok2 = "FullTextScan" in plan2_s
    print("  %s 全文索引：%s" % ("✓" if ok2 else "✗", "FullTextScan" if ok2 else plan2_s[:120]))
    if not ok2:
        bad += 1

    print()
    if bad:
        print("✗ 初始化完成但有 %d 项体检未通过" % bad)
        return 1
    print("✓ 初始化完成，全部体检通过")
    print()
    print("下一步：python3 query.py \"索引怎么用\" --tenant acme")
    return 0


if __name__ == "__main__":
    sys.exit(main())
