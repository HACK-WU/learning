#!/usr/bin/env python3
"""一次性校验：managed-deep-agents 教程的相对链接可达性 + SVG 合法性。"""
import os
import re
import sys
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

LINK_RE = re.compile(r"\[([^\]]*)\]\(([^)]+)\)")
FENCE_RE = re.compile(r"^```")
INLINE_CODE_RE = re.compile(r"`+[^`]*`+")


def strip_inline_code(line):
    """把行内代码替换成等长空白，保留列位置，避免把语法示例当成真链接。"""
    return INLINE_CODE_RE.sub(lambda m: " " * len(m.group(0)), line)


def iter_md(root):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in {"node_modules", ".git", ".mda"}]
        for name in filenames:
            if name.endswith(".md"):
                yield os.path.join(dirpath, name)


def strip_fences(text):
    """把围栏代码块内容替换成空行，避免把代码里的括号当链接。"""
    out, in_fence = [], False
    for line in text.splitlines():
        if FENCE_RE.match(line.strip()):
            in_fence = not in_fence
            out.append("")
            continue
        out.append("" if in_fence else line)
    return out


def check_links():
    dead = []
    total = 0
    for md in iter_md(ROOT):
        try:
            raw = open(md, encoding="utf-8").read()
        except UnicodeDecodeError:
            dead.append((md, "<解码失败>", ""))
            continue
        for lineno, line in enumerate(strip_fences(raw), 1):
            for m in LINK_RE.finditer(strip_inline_code(line)):
                target = m.group(2).strip()
                if target.startswith(("http://", "https://", "#", "mailto:")):
                    continue
                target = target.split("#")[0].split("?")[0]
                if not target:
                    continue
                total += 1
                path = os.path.normpath(os.path.join(os.path.dirname(md), target))
                if not os.path.exists(path):
                    dead.append((md, lineno, target))
    return total, dead


def check_svgs():
    bad, count = [], 0
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in {"node_modules", ".git"}]
        for name in filenames:
            if not name.endswith(".svg"):
                continue
            count += 1
            p = os.path.join(dirpath, name)
            try:
                ET.parse(p)
            except ET.ParseError as e:
                bad.append((p, str(e)))
    return count, bad


def check_placeholders():
    hits = []
    for md in iter_md(ROOT):
        raw = open(md, encoding="utf-8").read()
        for lineno, line in enumerate(raw.splitlines(), 1):
            if "待建" in line or "待补" in line or "TBD" in line or "TODO" in line:
                hits.append((md, lineno, line.strip()[:120]))
    return hits


def main():
    total, dead = check_links()
    svg_count, bad_svg = check_svgs()
    ph = check_placeholders()

    print(f"相对链接：{total} 条，死链 {len(dead)} 条")
    for md, lineno, target in dead:
        print(f"  DEAD {os.path.relpath(md, ROOT)}:{lineno} -> {target}")

    print(f"\nSVG：{svg_count} 个，非法 {len(bad_svg)} 个")
    for p, err in bad_svg:
        print(f"  BAD {os.path.relpath(p, ROOT)}: {err}")

    print(f"\n占位词命中：{len(ph)} 处")
    for md, lineno, line in ph:
        print(f"  {os.path.relpath(md, ROOT)}:{lineno}  {line}")

    return 0 if not dead and not bad_svg else 1


if __name__ == "__main__":
    sys.exit(main())
