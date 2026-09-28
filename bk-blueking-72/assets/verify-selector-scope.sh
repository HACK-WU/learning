#!/usr/bin/env bash
# 核查：seq=first 渲染出 paas3/bk-user 是否异常
set -uo pipefail
export PATH=/root/bk72/install/bin:$PATH
HF=/root/bk72/install/bin/helmfile
B=/root/bk72/install/blueking
cd "$B" || exit 1

echo "===== 1. selector 到底选中了几个 release ====="
$HF -f base.yaml.gotmpl -l seq=first list 2>&1 | grep -v 'skipping' | head -10

echo ""
echo "===== 2. 不带 selector 时总 release 数（对比）====="
$HF -f base.yaml.gotmpl list 2>&1 | grep -v 'skipping' | wc -l

echo ""
echo "===== 3. 检查 needs 依赖（可能导致额外渲染）====="
grep -n 'needs:' -A3 "$B/base-blueking.yaml.gotmpl" | head -20
echo "--- first 批 release 是否声明 needs ---"
python3 - <<'PY'
import re
txt=open('/root/bk72/install/blueking/base-blueking.yaml.gotmpl').read()
blocks=re.split(r'\n  - name: ', txt)
for b in blocks:
    name=b.split('\n')[0].strip()
    seq=re.search(r'seq:\s*(\S+)', b)
    needs=re.search(r'needs:', b)
    if seq and seq.group(1)=='first':
        print(f"  {name}: needs={'有' if needs else '无'}")
PY

echo ""
echo "===== 4. 渲染输出里 paas3 出现次数（判断是否真被部署）====="
grep -c 'paas3' /tmp/render-first.yaml
echo "--- 若 >0，看是哪些资源 ---"
grep -B2 -A2 'paas3-apiserver' /tmp/render-first.yaml | head -12

echo ""
echo "===== 5. helmfile 版本对 selector 的支持 ====="
$HF version
