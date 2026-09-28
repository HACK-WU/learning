#!/usr/bin/env bash
BASE="/mnt/d/projects/learning/bk-blueking-72"
cd "$BASE" || exit 1

add_banner() {
  f="$1"; shift
  title="$1"; shift
  body="$1"
  [ -f "$f" ] || { echo "    缺失: $f"; return; }
  grep -q '过时时点' "$f" && { echo "    已有标注: $f"; return; }
  python3 - "$f" "$title" "$body" <<'PY'
import sys,io
f,title,body=sys.argv[1],sys.argv[2],sys.argv[3]
lines=open(f,encoding='utf-8').read().split('\n')
# 跳过 H1
i=0
while i<len(lines) and not lines[i].startswith('# '): i+=1
i+=1
banner=['','> ⚠️ **本文档状态：历史快照（过时时点 2026-09-23）**',
        '>',
        '> ' + body,
        '>',
        '> **最新终态请看**：[25-部署验收总报告-全8批合并.md](25-部署验收总报告-全8批合并.md)（2026-09-24，实测）','']
out=lines[:i]+banner+lines[i:]
open(f,'w',encoding='utf-8').write('\n'.join(out))
print("    已加标注: %s"%f)
PY
}

echo "=== 给 9-23 快照类文档加过时标注 ==="
add_banner "08-实战经验.md" "" "决策复盘写于 9-23，其中「Pod 131 个 / 内存峰值 37%」等为**当时快照**。9-24 八批验证后终态为 **Pod 95 Running / 12 Completed，内存 used 36G**。方法论部分仍然有效。"
add_banner "10-访问指南.md" "" "写于 9-23 并实测通过。9-24 有变化：**监控 `bkmonitor` 503 已解除**（第 7 批验通）；`bkrepo` 页面因验后裁副本为 0 而 503（预期）。域名清单与登录凭据仍有效。"
add_banner "11-组件部署清单.md" "" "写于 9-23，记录「23 release / 133 Pod」。9-24 补装 monitor、nodeman、kafka、consul、influxdb 后**实测为 28 release / 95 Running**。缺 12 模块的判断已被补装动作覆盖。"
add_banner "11-组件镜像与源码对照.md" "" "镜像与源码对照，内容稳定。注意本环境**主线是 7.2 CE**，表中「蓝鲸 Lite」行属并行支线。"
add_banner "12-WSL内存调优与集群稳定性.md" "" "WSL 内存调优方法仍然有效，数值为 9-23 快照。"
add_banner "14-后台任务裁剪方案.md" "" "**注意状态变化**：此「永久裁剪」方案从未执行。9-24 实际执行的是**验完临时缩容为 0**（组件仍在，可再拉起），非永久删除。见档案 E.10 说明。"
add_banner "15-部署流程走通性核验.md" "" "部署流程走通性核验，属过程记录。"
add_banner "16-分批启动验证方案.md" "" "分批验证的**方案**文档。实际执行结果见各批报告与 [25-部署验收总报告](25-部署验收总报告-全8批合并.md)。"

echo ""
echo "=== 校验：标注后的文档 H1 之后是否有 banner ==="
for f in 08-实战经验.md 10-访问指南.md 11-组件部署清单.md 12-WSL内存调优与集群稳定性.md 14-后台任务裁剪方案.md; do
  c=$(grep -c '过时时点' "$f" 2>/dev/null)
  printf "    %-45s banner=%s\n" "$f" "$c"
done
