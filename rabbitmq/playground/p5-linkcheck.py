# -*- coding: utf-8 -*-
"""全库 Markdown 链接有效性 + 卫生检查。"""
import io
import os
import re
import sys

ROOT = "/mnt/d/projects/learning/rabbitmq"
if not os.path.exists(ROOT):
    ROOT = "D:/projects/learning/rabbitmq"

LINK_RE = re.compile(r"\[([^\]!]+)\]\(([^)]+)\)")
ANCHOR_RE = re.compile(r"^#+\s+(.+)$", re.M)

SKIP_DIRS = {"assets", ".git", "__pycache__"}


def slugify(text):
    """把标题文本转成 GitHub 风格的锚点。"""
    t = text.strip().lower()
    # 去掉 markdown 行内格式与 emoji
    t = re.sub(r"`([^`]*)`", r"\1", t)
    t = re.sub(r"\*\*([^*]*)\*\*", r"\1", t)
    t = re.sub(r"^\s*[^\w\s\u4e00-\u9fff]+\s*", "", t)
    t = re.sub(r"[^\w\s\u4e00-\u9fff-]", "", t)
    t = t.replace(" ", "-")
    return t


def collect_anchors(text):
    out = set()
    for m in ANCHOR_RE.finditer(text):
        out.add(slugify(m.group(1)))
    return out


def walk_md():
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for fn in filenames:
            if fn.endswith(".md"):
                yield os.path.join(dirpath, fn)


def main():
    md_files = list(walk_md())
    # 预读所有文件内容
    contents = {}
    anchors = {}
    for path in md_files:
        with io.open(path, "r", encoding="utf-8") as f:
            text = f.read()
        contents[path] = text
        anchors[path] = collect_anchors(text)

    failures = []
    checked = 0

    for path in md_files:
        text = contents[path]
        for m in LINK_RE.finditer(text):
            label, target = m.group(1).strip(), m.group(2).strip()
            checked += 1
            if target.startswith(("http://", "https://", "mailto:")):
                continue
            if target.startswith("#"):
                frag = target[1:]
                if slugify(frag) not in anchors[path]:
                    failures.append("[%s] 页内锚点不存在: %s"
                                    % (os.path.relpath(path, ROOT), target))
                continue

            # 拆分 path#anchor
            if "#" in target:
                tpath, frag = target.split("#", 1)
            else:
                tpath, frag = target, None

            resolved = os.path.normpath(os.path.join(os.path.dirname(path), tpath))
            if not os.path.exists(resolved):
                failures.append("[%s] 链接目标不存在: %s"
                                % (os.path.relpath(path, ROOT), target))
                continue
            if frag and resolved in anchors:
                if slugify(frag) not in anchors[resolved]:
                    failures.append("[%s] 跨文件锚点不存在: %s"
                                    % (os.path.relpath(path, ROOT), target))

    print("=" * 60)
    print("链接检查：%d 个 Markdown 文件，%d 条链接" % (len(md_files), checked))
    if failures:
        print("❌ 失败 %d 项：" % len(failures))
        for f in failures:
            print("   - " + f)
    else:
        print("✅ 全部链接有效")

    # 卫生检查：临时文件
    junk = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in {".git"}]
        for fn in filenames:
            if fn.endswith((".pyc", ".tmp", ".bak", ".orig")) or fn.startswith("~$"):
                junk.append(os.path.join(dirpath, fn))
            if fn.startswith("_insert") or fn.startswith("_tmp"):
                junk.append(os.path.join(dirpath, fn))

    print("-" * 60)
    if junk:
        print("⚠️  发现临时文件 %d 个：" % len(junk))
        for j in junk:
            print("   - " + os.path.relpath(j, ROOT))
    else:
        print("✅ 无残留临时文件")

    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
