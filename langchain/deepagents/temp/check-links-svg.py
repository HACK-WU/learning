#!/usr/bin/env python3
"""Deep Agents 教程 · 死链与 SVG 校验。

用法（在 deepagents 目录内）：
    python3 temp/check-links-svg.py

校验两类问题：
1. Markdown 相对链接指向的文件是否存在（跳过 http/https/mailto/纯锚点）
2. assets 下所有 .svg 是否为合法 XML

只报告，不修改。
"""

from __future__ import annotations

import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parent.parent

# 这些目录里的 md 不做链接校验
SKIP_DIRS = {"node_modules", ".git", "temp", "web-index"}

# 匹配 [text](target) 与 [text](target "title")
MD_LINK = re.compile(r"\[[^\]]*\]\(([^)]+)\)")

# 跳过这些协议
SKIP_SCHEMES = ("http://", "https://", "mailto:", "tel:", "ftp://", "#")


def iter_md_files() -> list[Path]:
    out: list[Path] = []
    for p in ROOT.rglob("*.md"):
        if any(part in SKIP_DIRS for part in p.relative_to(ROOT).parts):
            continue
        out.append(p)
    return sorted(out)


def iter_svg_files() -> list[Path]:
    out: list[Path] = []
    for p in ROOT.rglob("*.svg"):
        if any(part in SKIP_DIRS for part in p.relative_to(ROOT).parts):
            continue
        out.append(p)
    return sorted(out)


def check_links(md_files: list[Path]) -> list[tuple[str, int, str, str]]:
    """返回 (文件, 行号, 链接, 原因) 列表。"""
    bad: list[tuple[str, int, str, str]] = []

    for md in md_files:
        text = md.read_text(encoding="utf-8", errors="replace")
        for lineno, line in enumerate(text.splitlines(), 1):
            # 去掉行内代码，避免把 `[x](y)` 当链接
            cleaned = re.sub(r"`[^`]*`", "", line)
            for m in MD_LINK.finditer(cleaned):
                raw = m.group(1).strip()
                # 去掉 title 部分： path "title"
                target = raw.split()[0] if raw.split() else raw
                target = target.strip("<>")

                if not target or target.startswith(SKIP_SCHEMES):
                    continue
                if target.startswith("#"):
                    continue

                # 去掉锚点与查询串
                path_part = target.split("#", 1)[0].split("?", 1)[0]
                if not path_part:
                    continue

                path_part = unquote(path_part)

                # 绝对路径（以 / 开头）视为站内根路径，不做本地校验
                if path_part.startswith("/"):
                    continue

                resolved = (md.parent / path_part).resolve()
                if not resolved.exists():
                    bad.append(
                        (str(md.relative_to(ROOT)), lineno, target, "目标不存在")
                    )

    return bad


def check_svgs(svg_files: list[Path]) -> list[tuple[str, str]]:
    bad: list[tuple[str, str]] = []
    for svg in svg_files:
        try:
            ET.parse(svg)
        except ET.ParseError as e:
            bad.append((str(svg.relative_to(ROOT)), f"XML 解析失败: {e}"))
        except Exception as e:  # noqa: BLE001
            bad.append((str(svg.relative_to(ROOT)), f"读取失败: {e}"))
    return bad


def main() -> int:
    md_files = iter_md_files()
    svg_files = iter_svg_files()

    print(f"[INFO] 扫描 Markdown {len(md_files)} 个、SVG {len(svg_files)} 个")
    print(f"[INFO] 根目录: {ROOT}")
    print()

    link_bad = check_links(md_files)
    svg_bad = check_svgs(svg_files)

    if link_bad:
        print(f"[FAIL] 死链 {len(link_bad)} 处：")
        for f, ln, target, why in link_bad:
            print(f"  {f}:{ln}  ->  {target}   ({why})")
    else:
        print("[OK] 相对链接：0 处死链")

    print()

    if svg_bad:
        print(f"[FAIL] SVG {len(svg_bad)} 个不合法：")
        for f, why in svg_bad:
            print(f"  {f}  ({why})")
    else:
        print(f"[OK] SVG：{len(svg_files)} 个全部为合法 XML")

    print()
    total = len(link_bad) + len(svg_bad)
    print(f"[RESULT] 合计问题 {total} 个")
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
