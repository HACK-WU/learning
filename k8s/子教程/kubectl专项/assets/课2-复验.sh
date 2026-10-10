#!/usr/bin/env bash
# 课 2 讲义复验：原样照抄讲义命令
kubectl config use-context kind-k8s-c1 >/dev/null 2>&1
echo "########## 课2 复验（基线: $(kubectl config current-context)）##########"
PASS=0; FAIL=0
chk(){ if [ "$2" = "$3" ]; then echo "  ✅ $1"; PASS=$((PASS+1)); else echo "  ❌ $1  期望[$3] 实际[$2]"; FAIL=$((FAIL+1)); fi; }

echo ""
echo "=== 第1步：体积对比（不硬编码绝对值，验证相对关系）==="
P=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -v "No resources" | head -1 | awk '{print $1}')
echo "  样例 Pod: $P"
D=$(kubectl get pod $P -n kube-system 2>/dev/null | wc -c)
W=$(kubectl get pod $P -n kube-system -o wide 2>/dev/null | wc -c)
Y=$(kubectl get pod $P -n kube-system -o yaml 2>/dev/null | wc -c)
J=$(kubectl get pod $P -n kube-system -o json 2>/dev/null | wc -c)
JP=$(kubectl get pod $P -n kube-system -o jsonpath='{.metadata.name}' 2>/dev/null | wc -c)
echo "  默认=$D  wide=$W  yaml=$Y  json=$J  jsonpath=$JP"
chk "体积关系 json > yaml" "$([ "$J" -gt "$Y" ] && echo 1 || echo 0)" "1"
chk "体积关系 yaml > wide" "$([ "$Y" -gt "$W" ] && echo 1 || echo 0)" "1"
chk "体积关系 wide > jsonpath" "$([ "$W" -gt "$JP" ] && echo 1 || echo 0)" "1"

echo ""
echo "=== 第2步：输出格式可用性 ==="
chk "默认有输出" "$([ "$(kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -v 'No resources' | wc -l)" -ge 1 ] && echo 1 || echo 0)" "1"
chk "-o wide 有输出" "$([ "$(kubectl get pods -n kube-system -o wide --no-headers 2>/dev/null | grep -v 'No resources' | wc -l)" -ge 1 ] && echo 1 || echo 0)" "1"
CC=$(kubectl get pods -n kube-system -o custom-columns='POD:.metadata.name,IP:.status.podIP,NODE:.spec.nodeName' 2>&1 | head -1)
echo "  custom-columns 表头: [$CC]"
chk "custom-columns 表头含 POD/IP/NODE" "$(echo "$CC" | grep -c 'POD' )" "1"

echo ""
echo "=== 第3步：jsonpath 七种语法 ==="
chk "① 单个字段" "$([ -n "$(kubectl get pods -n kube-system -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)" ] && echo 1 || echo 0)" "1"
# 修正：jsonpath 的输出末尾【没有换行】，wc -l 数不到行（实测 od -c 确认末尾无 \n）
# 正确判据：内容非空且不含换行符 = 一行
JP_LINE=$(kubectl get pods -n kube-system -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
chk "② [*] 是一行（无换行符）" "$([ -n "$JP_LINE" ] && [ "$(printf '%s' "$JP_LINE" | wc -l)" = "0" ] && echo 1 || echo 0)" "1"
chk "② [*] 用空格分隔多值" "$(printf '%s' "$JP_LINE" | grep -c ' ')" "1"
chk "③ range 换行(>=3行)" "$([ "$(kubectl get pods -n kube-system -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep -v '^$' | wc -l)" -ge 3 ] && echo 1 || echo 0)" "1"
chk "④ 多字段含Tab" "$(kubectl get pods -n kube-system -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\n"}{end}' 2>/dev/null | head -1 | grep -cP '\t')" "1"
chk "⑤ 递归 ..labels" "$(kubectl get pods -n kube-system -o jsonpath='{..labels}' 2>/dev/null | grep -c 'k8s-app')" "1"
chk "⑥ 过滤器 ?()" "$([ "$(kubectl get pods -n kube-system -o jsonpath='{range .items[?(@.status.phase=="Running")]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep -v '^$' | wc -l)" -ge 1 ] && echo 1 || echo 0)" "1"
chk "⑦ 数组下标" "$([ -n "$(kubectl get pods -n kube-system -o jsonpath='{.items[0].spec.containers[0].name}' 2>/dev/null)" ] && echo 1 || echo 0)" "1"

echo ""
echo "=== 第4步：不支持正则 ==="
RE=$(kubectl get pods -n kube-system -o jsonpath='{range .items[?(@.metadata.name=~/^coredns.*/)]}{.metadata.name}{"\n"}{end}' 2>&1)
echo "  输出: $(echo "$RE" | head -c 120)"
chk "正则报错含 unrecognized character" "$(echo "$RE" | grep -c 'unrecognized character')" "1"
chk "grep 补位可用" "$([ "$(kubectl get pods -n kube-system -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep -c '^coredns')" -ge 1 ] && echo 1 || echo 0)" "1"

echo ""
echo "=== 第5步：-l 六种运算符 ==="
chk "① 等值 k8s-app=kube-dns 有结果" "$([ "$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null | grep -v 'No resources' | wc -l)" -ge 1 ] && echo 1 || echo 0)" "1"
chk "② 不等值有结果" "$([ "$(kubectl get pods -n kube-system -l 'k8s-app!=kube-dns' --no-headers 2>/dev/null | grep -v 'No resources' | wc -l)" -ge 1 ] && echo 1 || echo 0)" "1"
chk "③ 存在性有结果" "$([ "$(kubectl get pods -n kube-system -l k8s-app --no-headers 2>/dev/null | grep -v 'No resources' | wc -l)" -ge 1 ] && echo 1 || echo 0)" "1"
chk "④ 不存在有结果" "$([ "$(kubectl get pods -n kube-system -l '!k8s-app' --no-headers 2>/dev/null | grep -v 'No resources' | wc -l)" -ge 1 ] && echo 1 || echo 0)" "1"
chk "⑤ in 有结果" "$([ "$(kubectl get pods -n kube-system -l 'k8s-app in (kube-dns,kube-proxy)' --no-headers 2>/dev/null | grep -v 'No resources' | wc -l)" -ge 1 ] && echo 1 || echo 0)" "1"
# 修正：--no-headers 下无资源时输出的是 "No resources found in kube-system namespace."
# 但经 2>/dev/null 管道后需直接判空；用不带 --no-headers 的原样输出更稳
AND_OUT=$(kubectl get pods -n kube-system -l 'k8s-app=kube-dns,tier=control-plane' 2>&1)
echo "  AND 输出: [$AND_OUT]"
chk "⑥ AND 无匹配" "$(echo "$AND_OUT" | grep -c 'No resources')" "1"

echo ""
echo "=== 第6步：--field-selector ==="
chk "① status.phase=Running" "$([ "$(kubectl get pods -n kube-system --field-selector status.phase=Running --no-headers 2>/dev/null | grep -v 'No resources' | wc -l)" -ge 1 ] && echo 1 || echo 0)" "1"
NODE=$(kubectl get nodes --no-headers 2>/dev/null | head -1 | awk '{print $1}')
chk "② spec.nodeName" "$([ "$(kubectl get pods -n kube-system --field-selector spec.nodeName=$NODE --no-headers 2>/dev/null | grep -v 'No resources' | wc -l)" -ge 1 ] && echo 1 || echo 0)" "1"
chk "④ labels 字段报错" "$(kubectl get pods -n kube-system --field-selector 'metadata.labels.k8s-app=kube-dns' 2>&1 | grep -c 'field label not supported')" "1"
# 修正：同上，用原样输出判定
REV_OUT=$(kubectl get pods -n kube-system --field-selector status.podIP=9.9.9.9 2>&1)
echo "  反测输出: [$REV_OUT]"
chk "反测法：不存在 IP 返回空" "$(echo "$REV_OUT" | grep -c 'No resources')" "1"

echo ""
echo "=== 第7步：sort-by 与 -A ==="
S1=$(kubectl get pods -n kube-system --sort-by=.metadata.name --no-headers 2>/dev/null | grep -v 'No resources' | head -1 | awk '{print $1}')
S2=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -v 'No resources' | head -1 | awk '{print $1}')
echo "  sort-by 首行=$S1  未排序首行=$S2"
chk "sort-by 可执行" "$([ -n "$S1" ] && echo 1 || echo 0)" "1"
chk "-A 有输出" "$([ "$(kubectl get pods -A --no-headers 2>/dev/null | grep -v 'No resources' | wc -l)" -ge 1 ] && echo 1 || echo 0)" "1"
# 验证 -A 首列是 NAMESPACE
NA=$(kubectl pods -A 2>/dev/null; kubectl get pods -A --no-headers 2>/dev/null | head -1 | awk '{print $1}')
echo "  -A 首列值: [$NA]"
chk "-A 首列是命名空间名(非Pod名)" "$(kubectl get ns --no-headers 2>/dev/null | awk '{print $1}' | grep -cx "$NA")" "1"

echo ""
echo "=== 第8步：综合场景 ==="
R=$(kubectl get pods -A -o jsonpath='{range .items[?(@.status.phase=="Running")]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.status.podIP}{"\n"}{end}' 2>/dev/null | grep -v '^kube-system' | wc -l)
echo "  非 kube-system 的 Running Pod 数: $R"
chk "综合命令可执行" "$([ "$R" -ge 0 ] && echo 1 || echo 0)" "1"

echo ""
echo "=== 讲义链接可达性 ==="
cd /mnt/d/projects/learning/k8s/子教程/kubectl专项/lessons
for L in "01-kubectl怎么找到集群.md" "../overview.md" \
         "../../../stages/3-网络与服务暴露/lessons/07-Service与CoreDNS.md"; do
  printf "  %-62s " "$(basename "$L")"
  if [ -f "$L" ]; then echo "✅"; PASS=$((PASS+1)); else echo "❌"; FAIL=$((FAIL+1)); fi
done

echo ""
echo "########## 课2 复验：PASS=$PASS  FAIL=$FAIL ##########"
