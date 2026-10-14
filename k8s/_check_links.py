import os
import re

ROOT = '/mnt/d/projects/learning/k8s'
SKIP = {'node_modules', '.venv', 'web-index', '.git'}
LINK_RE = re.compile(r'\[([^\]]*)\]\(([^)]+)\)')
# 占位符 / 语法示例说明文字（如正文里讲解 `![...](...)` 时写的 `...`），非真实链接
# 仅匹配"纯省略号"，不匹配 `./foo.md` 等任何含字母或斜杠前缀的真实相对路径
PLACEHOLDER_RE = re.compile(r'^\s*(?:[.…]{2,}|…)\s*$')

bad = []
skipped = []
total = 0
for dirpath, dirnames, filenames in os.walk(ROOT):
    dirnames[:] = [d for d in dirnames if d not in SKIP]
    for fn in filenames:
        if not fn.endswith('.md'):
            continue
        full = os.path.join(dirpath, fn)
        try:
            with open(full, encoding='utf-8') as f:
                lines = f.readlines()
        except Exception:
            continue
        for i, line in enumerate(lines, 1):
            for m in LINK_RE.finditer(line):
                link = m.group(2)
                if link.startswith(('http', 'mailto', '#')):
                    continue
                clean = link.split('#')[0]
                if not clean.strip():
                    continue
                if PLACEHOLDER_RE.match(clean):
                    skipped.append((os.path.relpath(full, ROOT), i, link))
                    continue
                total += 1
                resolved = os.path.normpath(os.path.join(dirpath, clean))
                if not os.path.exists(resolved):
                    bad.append((os.path.relpath(full, ROOT), i, link))

print("TOTAL local links: %d" % total)
print("BAD: %d" % len(bad))
print("SKIPPED(占位符/语法示例): %d" % len(skipped))
print("")
print("########## 真实坏链清单 ##########")
for f, l, link in bad:
    print("%s:%d -> %s" % (f, l, link))
if not bad:
    print("（无）")
print("")
print("########## 已跳过（占位符，非真链接）##########")
for f, l, link in skipped:
    print("%s:%d -> %s" % (f, l, link))
if not skipped:
    print("（无）")

print("")
print("########## 按目标归类 ##########")
from collections import Counter
c = Counter(link for _, _, link in bad)
for link, n in c.most_common():
    print("%3d  %s" % (n, link))

print("")
print("########## 自校验：抽 5 条应存在的链接 ##########")
checks = [
    '应用实战/INDEX.md',
    '00-环境准备.md',
    '02-课程目录.md',
    '子教程/运维专项/overview.md',
    '场景解法库/INDEX.md',
]
for ck in checks:
    p = os.path.join(ROOT, ck)
    print(("  OK  " if os.path.exists(p) else "  MISS") + " " + ck)

print("")
print("########## 自校验：占位符白名单不得吞掉真实路径 ##########")
guard = [
    ('.../02-课程目录.md', False),   # 含真实文件名，不该被吞
    ('../02-课程目录.md', False),
    ('./02-课程目录.md', False),
    ('...', True),
    ('…', True),
    ('  ...  ', True),
]
ok = True
for sample, should_skip in guard:
    got = bool(PLACEHOLDER_RE.match(sample))
    flag = "  OK  " if got == should_skip else "  FAIL"
    if got != should_skip:
        ok = False
    print("%s %-22r skip=%s (期望 %s)" % (flag, sample, got, should_skip))
print("白名单自校验：" + ("通过" if ok else "失败"))
