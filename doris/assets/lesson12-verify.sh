#!/bin/bash
# 课 12 交付校验：62 项
# 用法：bash lesson12-verify.sh
# 任一 FAIL 都必须修掉才能交付

LESSON="stages/4-分布式运维与生产落地/lessons/lesson-12-选型存算分离与场景落地.md"
ASSETS="assets"
SVG1="stages/4-分布式运维与生产落地/assets/lesson-12-boundary.svg"
SVG2="stages/4-分布式运维与生产落地/assets/lesson-12-storage.svg"

PASS=0; FAIL=0
ok()   { echo "  [OK]   $1"; PASS=$((PASS+1)); }
bad()  { echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }
chk()  { if [ "$2" = "0" ]; then ok "$1"; else bad "$1"; fi; }

# 排除接力提示词段落（里面出现的规范条文不算正文问题），保留其后的课程导航
BODY=$(awk '/^## 🚀 下一批接力提示词/{skip=1;next} /^## 🧭 课程导航/{skip=0} skip==0{print}' "$LESSON")

echo "=============================================="
echo " A. 文件存在性（8 项）"
echo "=============================================="
[ -f "$LESSON" ] && ok "正文存在" || bad "正文不存在"
[ -f "$SVG1" ] && ok "SVG1 边界图存在" || bad "SVG1 边界图缺失"
[ -f "$SVG2" ] && ok "SVG2 存算分离图存在" || bad "SVG2 存算分离图缺失"
for f in lesson12-setup.sh lesson12-step1.sh lesson12-step2.sh lesson12-step3.sh lesson12-cleanup.sh; do
  [ -f "$ASSETS/$f" ] && ok "脚本 $f 存在" || bad "脚本 $f 缺失"
done

echo ""
echo "=============================================="
echo " B. 必备段落（12 项）"
echo "=============================================="
for s in "## 🎯 本课目标" "## ⚠️ 实验边界表" "## 第一幕" "## 第二幕" "## 第三幕" \
         "### 知识点 1：Doris 与同类系统对比" "### 知识点 2：存算分离架构" \
         "### 知识点 3：典型场景架构与反模式" "## 第四幕" "## 第五幕" \
         "## 🐞 常见误区" "## 一图总结" "## 📚 速览表" "## 🎓 小测" \
         "## 🧭 课程导航"; do
  echo "$BODY" | grep -qF "$s" && ok "段落：$s" || bad "缺段落：$s"
done
# 接力提示词段落被 BODY 有意排除（里面是规范条文），单独在全文上检查
grep -qF "## 🚀 下一批接力提示词" "$LESSON" && ok "段落：## 🚀 下一批接力提示词" || bad "缺段落：接力提示词"

echo ""
echo "=============================================="
echo " C. 边界标注（8 项）"
echo "=============================================="
C1=$(echo "$BODY" | grep -oE "🟢[^|]{0,4}已实测" | wc -l)
C2=$(echo "$BODY" | grep -oE "🟡[^|]{0,6}部分实测" | wc -l)
C3=$(echo "$BODY" | grep -oE "🔴[^|]{0,4}未实测" | wc -l)
[ "$C1" -ge 10 ] && ok "🟢 已实测标记 $C1 处（>=10）" || bad "🟢 已实测仅 $C1 处"
[ "$C2" -ge 1 ] && ok "🟡 部分实测标记 $C2 处（>=1）" || bad "🟡 部分实测仅 $C2 处"
[ "$C3" -ge 5 ] && ok "🔴 未实测标记 $C3 处（>=5）" || bad "🔴 未实测仅 $C3 处"
echo "$BODY" | grep -qF "RemoteUsedCapacity" && ok "有存算一体的铁证" || bad "缺存算一体铁证"
echo "$BODY" | grep -qF "only support in cloud mode" && ok "有 cloud mode 报错原文" || bad "缺 cloud mode 报错"
echo "$BODY" | grep -qF "jieba.dict.utf8" && ok "有中文分词字典报错" || bad "缺中文分词字典报错"
echo "$BODY" | grep -qF "ROLLBACK" && ok "有 ROLLBACK 相关说明" || bad "缺 ROLLBACK 说明"
echo "$BODY" | grep -qF "看趋势" && ok "有数值浮动说明" || bad "缺数值浮动说明"

echo ""
echo "=============================================="
echo " D. 数据一致性（10 项）"
echo "=============================================="
# 与实测对齐的关键数字
echo "$BODY" | grep -qF "0.13" && ok "有扫 1 列耗时 0.13" || bad "缺扫 1 列耗时"
echo "$BODY" | grep -qF "0.51" && ok "有扫 13 列耗时 0.51" || bad "缺扫 13 列耗时"
echo "$BODY" | grep -qF "5.7" && ok "有点查延迟 5.7ms" || bad "缺点查延迟"
echo "$BODY" | grep -qF "0.40" && ok "有共享存储明细 0.40" || bad "缺共享存储明细耗时"
echo "$BODY" | grep -qF "3 倍" && ok "有明细差 3 倍结论" || bad "缺明细 3 倍结论"
echo "$BODY" | grep -qF "314 万" && ok "有 314 万行数据量" || bad "缺数据量说明"
echo "$BODY" | grep -qF "2150 万" && ok "有 2150 万行数据量" || bad "缺 orders 数据量"
echo "$BODY" | grep -qF "7894118180.53" && ok "有 parquet 校验指纹" || bad "缺校验指纹"
# 反向断言：不能出现编造的同类系统跑分
if echo "$BODY" | grep -qE "ClickHouse.*[0-9]+\.[0-9]+ *秒|比 ClickHouse 快.*倍"; then
  bad "出现 ClickHouse 具体跑分（应标未实测）"
else
  ok "无 ClickHouse 编造跑分"
fi
if echo "$BODY" | grep -qE "比 Elasticsearch 快.*倍|ES.*[0-9]+ms 而 Doris"; then
  bad "出现 ES 具体跑分（应标未实测）"
else
  ok "无 ES 编造跑分"
fi

echo ""
echo "=============================================="
echo " E. 报错原文保留（8 项）"
echo "=============================================="
for e in "only support in cloud mode" \
         "Storage Vault is only supported for cloud mode" \
         "no viable alternative at input 'SHOW CACHE'" \
         "chinese tokenizer dict file not found" \
         "No such file or directory" \
         "Can not build s3" \
         "unsupported column type" \
         "Do not support external table with engine name"; do
  if echo "$BODY" | grep -qF "$e"; then ok "报错原文：$e"; else bad "缺报错原文：$e"; fi
done

echo ""
echo "=============================================="
echo " F. 脚本可运行性（8 项）"
echo "=============================================="
for f in lesson12-setup.sh lesson12-step1.sh lesson12-step2.sh lesson12-step3.sh lesson12-cleanup.sh; do
  bash -n "$ASSETS/$f" 2>/dev/null && ok "语法 OK：$f" || bad "语法错误：$f"
done
grep -q "docker exec -i" "$ASSETS/lesson12-step1.sh" && ok "step1 用了 docker exec -i" || bad "step1 缺 -i"
grep -q "docker exec -i" "$ASSETS/lesson12-step2.sh" && ok "step2 用了 docker exec -i" || bad "step2 缺 -i"
grep -q "docker exec -i" "$ASSETS/lesson12-step3.sh" && ok "step3 用了 docker exec -i" || bad "step3 缺 -i"

echo ""
echo "=============================================="
echo " G. 图与引用（6 项）"
echo "=============================================="
grep -q "lesson-12-boundary.svg" "$LESSON" && ok "正文引用边界图" || bad "正文未引用边界图"
grep -q "lesson-12-storage.svg" "$LESSON" && ok "正文引用存算分离图" || bad "正文未引用存算分离图"
head -1 "$SVG1" | grep -q "<svg" && ok "SVG1 是合法 SVG" || bad "SVG1 格式错误"
head -1 "$SVG2" | grep -q "<svg" && ok "SVG2 是合法 SVG" || bad "SVG2 格式错误"
grep -q "lesson-11" "$LESSON" && ok "有上一课导航链接" || bad "缺上一课导航"
grep -q "02-课程目录.md" "$LESSON" && ok "有课程目录链接" || bad "缺课程目录链接"

echo ""
echo "=============================================="
echo " H. 正文质量（8 项）"
echo "=============================================="
# 禁止省略形式（排除接力段）
if echo "$BODY" | grep -qE "（同上）|\(同上\)|列定义同上"; then
  bad "正文中出现省略形式"
else
  ok "无省略形式"
fi
# 小测有答案
DETAILS=$(echo "$BODY" | grep -c "<details>")
[ "$DETAILS" -ge 3 ] && ok "小测有 $DETAILS 个可展开答案（>=3）" || bad "小测答案仅 $DETAILS 个"
# 误区数量
MYTH=$(echo "$BODY" | sed -n '/## 🐞 常见误区/,/## 一图总结/p' | grep -cE "^\*\*误区 [0-9]+")
[ "$MYTH" -ge 8 ] && ok "误区有 $MYTH 条（>=8）" || bad "误区仅 $MYTH 条"
# 反模式数量
ANTI=$(echo "$BODY" | grep -cE "^#### 3\.[0-9]+ 反模式")
[ "$ANTI" -ge 5 ] && ok "反模式有 $ANTI 个（>=5）" || bad "反模式仅 $ANTI 个"
# 全课程回扣
echo "$BODY" | grep -qF "课 9" && ok "有回扣课 9" || bad "缺课 9 回扣"
echo "$BODY" | grep -qF "课 10" && ok "有回扣课 10" || bad "缺课 10 回扣"
echo "$BODY" | grep -qF "课 11" && ok "有回扣课 11" || bad "缺课 11 回扣"
LINES=$(wc -l < "$LESSON")
[ "$LINES" -ge 1000 ] && ok "正文 $LINES 行（>=1000）" || bad "正文仅 $LINES 行"

echo ""
echo "=============================================="
echo " 校验结果：PASS=$PASS  FAIL=$FAIL"
echo "=============================================="
if [ "$FAIL" -eq 0 ]; then echo "VERIFY_OK"; else echo "VERIFY_FAIL"; exit 1; fi
