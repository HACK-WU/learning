#!/usr/bin/env bash
# 综合实战项目交付前检查
#  1. 四份文档是否齐全
#  2. 文档里的所有本地链接是否可达
#  3. 可运行脚本的完整性
#  4. 文档与实测结果的一致性抽查
set -uo pipefail
PROJ="/mnt/d/projects/learning/victoriametrics/projects/多租户监控平台"
ERR=0
ok(){ echo "  [OK] $*"; }
ng(){ echo "  [NG] $*"; ERR=$((ERR+1)); }
hdr(){ echo; echo "=== $* ==="; }

hdr "1. 四份文档齐全性"
for f in README.md 设计决策.md 反例对照.md 验收清单.md; do
  [ -f "$PROJ/$f" ] && ok "$f ($(wc -l < "$PROJ/$f") 行)" || ng "缺失 $f"
done

hdr "2. 实现目录清单"
ls -1 "$PROJ/实现" | sed 's/^/  /'

hdr "3. 本地链接可达性"
python3 - "$PROJ" <<'PY'
import os,re,sys
proj=sys.argv[1]
bad=0; total=0
for root,_,files in os.walk(proj):
    for fn in files:
        if not fn.endswith('.md'): continue
        p=os.path.join(root,fn)
        try: txt=open(p,encoding='utf-8').read()
        except Exception: continue
        for m in re.finditer(r'\[([^\]]*)\]\(([^)]+)\)', txt):
            url=m.group(2)
            if url.startswith(('http://','https://','#','mailto:')): continue
            url=url.split('#')[0]
            if not url: continue
            total+=1
            target=os.path.normpath(os.path.join(root, url))
            if not os.path.exists(target):
                print("  [NG] %s -> %s" % (os.path.relpath(p,proj), url)); bad+=1
print("  链接总数 = %d，失效 = %d" % (total, bad))
PY

hdr "4. 脚本可执行性（语法检查）"
for s in "$PROJ"/实现/*.sh; do
  [ -f "$s" ] || continue
  if bash -n "$s" 2>/dev/null; then
    ok "$(basename "$s") 语法正确"
  else
    ng "$(basename "$s") 语法错误"
  fi
done

hdr "5. Python 语法检查"
python3 -m py_compile "$PROJ/实现/exporter.py" 2>/dev/null \
  && ok "exporter.py 语法正确" || ng "exporter.py 语法错误"

hdr "6. 文档与实测数字一致性抽查"
# 这些数字必须与 p02-verify.sh / p14-failover.sh 的实际输出一致
check(){ if grep -q "$2" "$PROJ/$1" 2>/dev/null; then ok "$1 含「$2」"; else ng "$1 缺「$2」"; fi; }
check README.md "14/14"
check README.md "6/6"
check README.md "0 行"
check README.md "400"
check README.md "401"
check 反例对照.md "absent(last_over_time"
check 反例对照.md "metric_relabel_configs"
check 设计决策.md "每租户一个 vmalert"
check 设计决策.md "2.3%"
check 验收清单.md "ScrapeStalled"
check 验收清单.md "50 条"

hdr "7. 关键词覆盖（课程要求的收尾要素）"
for kw in "覆盖知识点地图" "非功能约束" "运行方式" "下一步"; do
  if grep -q "$kw" "$PROJ/README.md"; then ok "README 含「$kw」"; else ng "README 缺「$kw」"; fi
done

hdr "8. 容器当前状态（确认环境是活的）"
docker ps --format '{{.Names}}' 2>/dev/null | grep -c '^capstone-' | xargs -I{} echo "  capstone-* 容器数 = {}"

echo
echo "============================================================"
if [ "$ERR" = "0" ]; then
  echo " 检查通过：0 项问题"
else
  echo " 检查完成：$ERR 项需要修复"
fi
echo "============================================================"
