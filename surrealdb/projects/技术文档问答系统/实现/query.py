# -*- coding: utf-8 -*-
"""query.py —— 命令行入口：提问并对比四种检索模式

用法：
    python3 query.py "索引怎么用"                     # 默认 hybrid，root 身份
    python3 query.py "权限怎么配" --mode kw           # 只看关键词
    python3 query.py "图遍历" --mode graph            # 混合 + 图扩展
    python3 query.py "事务" --user alice@acme.io      # 以租户用户身份问（走权限）
    python3 query.py "索引" --compare                 # 四种模式横向对比

--user 模式是本项目权限相关性的关键：同一个问题，alice(acme) 与 bob(beta)
看到的结果不同，因为表级 PERMISSIONS 按 tenant 过滤。
"""
import sys
import os
import argparse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import Conn, NS, DB, fmt_ms  # noqa: E402
from retrieve import Retriever, measure  # noqa: E402
from seed import DEFAULT_PASSWORD  # noqa: E402


def shorten(s, n=78):
    s = (s or "").replace("\n", " ")
    return s if len(s) <= n else s[:n] + "…"


def show(rows, title, with_score=True):
    print()
    print("─" * 78)
    print(title)
    print("─" * 78)
    if not rows:
        print("  （无结果）")
        return
    for i, r in enumerate(rows, 1):
        why = r.get("why", "")
        sc = r.get("score")
        head = "[%d] %s  %s" % (i, r.get("id", "?"), why)
        if with_score and sc is not None:
            head += "  score=%s" % round(float(sc), 4)
        print(head)
        print("     %s" % shorten(r.get("text"), 96))


def main():
    ap = argparse.ArgumentParser(description="技术文档问答系统 · 检索")
    ap.add_argument("question", help="要问的问题")
    ap.add_argument("--mode", default="hybrid",
                    choices=["kw", "vec", "hybrid", "graph"], help="检索模式")
    ap.add_argument("--user", default=None, help="以该邮箱的用户身份提问（走权限）")
    ap.add_argument("--password", default=DEFAULT_PASSWORD)
    ap.add_argument("--k", type=int, default=5, help="返回条数")
    ap.add_argument("--compare", action="store_true", help="四种模式对比")
    args = ap.parse_args()

    if args.user:
        boot = Conn()
        try:
            token = boot.signin("app", email=args.user, password=args.password)
        except RuntimeError as e:
            print("✗ 登录失败：%s" % e)
            print("  提示：默认密码 %s；用户见 seed.py 的 USERS" % DEFAULT_PASSWORD)
            return 1
        conn = Conn(token=token)
        tenant = None  # 由服务端 PERMISSIONS 过滤，客户端不再加条件
        who = "%s（记录用户，受 PERMISSIONS 约束）" % args.user
    else:
        conn = Conn()
        tenant = None
        who = "root（系统用户，不受 PERMISSIONS 约束）"

    print("=" * 78)
    print("问题：%s" % args.question)
    print("身份：%s     NS=%s DB=%s" % (who, NS, DB))
    print("=" * 78)

    if args.compare:
        print()
        print("%-10s %-10s %s" % ("模式", "服务端ms", "Top3 id"))
        print("-" * 78)
        for mode in ["kw", "vec", "hybrid", "graph"]:
            rows, med, err = measure(conn, args.question, mode, tenant, k=args.k)
            if err:
                print("%-10s %-10s 失败：%s" % (mode, "-", str(err)[:60]))
                continue
            top = ", ".join(str(r.get("id", "?")).replace("chunk:", "")
                            for r in (rows or [])[:3])
            print("%-10s %-10s %s" % (mode,
                                      ("%.2f" % med) if med is not None else "-",
                                      top))
        for mode in ["kw", "vec", "hybrid", "graph"]:
            rows, _, err = measure(conn, args.question, mode, tenant,
                                   k=args.k, repeat=1)
            if not err and rows:
                show(rows, "模式 = %s" % mode)
        return 0

    r = Retriever(conn, tenant=tenant, k=args.k)
    rows = r.search(args.question, mode=args.mode, limit=args.k)
    show(rows, "模式 = %s，返回 %d 条" % (args.mode, len(rows)))

    # 权限提示：让"为什么结果变少"这件事可见
    if args.user:
        root_rows = Retriever(Conn(), k=args.k).search(
            args.question, mode=args.mode, limit=args.k)
        print()
        print("─" * 78)
        print("权限对照（同一问题，root 身份 vs 用户身份）")
        print("  root 可见：%d 条    当前用户可见：%d 条"
              % (len(root_rows), len(rows)))
        if len(root_rows) > len(rows):
            print("  差 %d 条 → 被表级 PERMISSIONS 按 tenant 过滤掉了"
                  % (len(root_rows) - len(rows)))
        elif len(root_rows) == len(rows):
            print("  无差异 → 本次命中的块都在本租户内（换 beta 的文档试试）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
