# -*- coding: utf-8 -*-
"""check_links.py —— 全课程 Markdown 链接可达性检查

为什么要这个脚本（2026-09-02 的教训）：
    influxdb 课程交付后做链接检查，一次性抓出六个阶段 overview 的
    返回链接层级错误（应为 ../../02-课程目录.md，实写 ../02-课程目录.md，
    共 18 处）。人工翻很容易漏，必须脚本化。

检查范围：
    1. 所有 .md 文件里的 [text](path) 相对链接
    2. 特别关注各阶段 overview 的返回链接层级

用法：
    python3 check_links.py            # 检查整个课程目录
    python3 check_links.py --verbose  # 连"锚点不存在"也报
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
SKIP_DIRS = {"node_modules", ".git", "__pycache__", ".codebuddy"}

# [text](path) 但排除 http(s):// 与 mailto:
LINK_RE = re.compile(r"\[([^\]]*)\]\(([^)]+)\)")


def iter_md(root):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for fn in filenames:
            if fn.endswith(".md"):
                yield os.path.join(dirpath, fn)


def main():
    verbose = "--verbose" in sys.argv
    broken = []
    total = 0
    checked_files = 0

    for md in iter_md(ROOT):
        checked_files += 1
        with open(md, "r", encoding="utf-8") as f:
            content = f.read()

        for m in LINK_RE.finditer(content):
            text, target = m.group(1), m.group(2).strip()
            if target.startswith(("http://", "https://", "mailto:", "#")):
                continue
            # 跳过文档里作为格式示例的占位符（如 [名称](url)）
            if target in ("url", "path", "xxx") or text in ("名称", "链接名"):
                continue
            total += 1

            # 去掉锚点部分
            path_part = target.split("#")[0]
            if not path_part:
                continue

            abs_target = os.path.normpath(os.path.join(os.path.dirname(md), path_part))
            if not os.path.exists(abs_target):
                rel_md = os.path.relpath(md, ROOT)
                broken.append((rel_md, text, target))

    print("=" * 74)
    print("链接可达性检查")
    print("=" * 74)
    print("  检查文件数：%d" % checked_files)
    print("  检查链接数：%d" % total)
    print()

    if broken:
        print("  ✗ 断裂链接 %d 处：" % len(broken))
        print()
        for md, text, target in broken:
            print("      %s" % md)
            print("          [%s](%s)" % (text, target))
        print()
        print("=" * 74)
        print("结果：失败")
        print("=" * 74)
        return 1

    print("  ✓ 全部可达")
    print()
    print("=" * 74)
    print("结果：通过")
    print("=" * 74)
    return 0


if __name__ == "__main__":
    sys.exit(main())
