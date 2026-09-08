set +x
BASE=/mnt/d/projects/learning/prometheus/labs/lesson-04
PROM=http://localhost:9094

echo "########## 复现：recording rule '查不到值' 的经典坑 ##########"
echo
echo "场景：新增一条 recording rule，reload 之后立刻查它——会返回空"
echo

# 1) 备份原规则文件
cp "$BASE/rules.yml" "$BASE/rules.yml.bak"

# 2) 追加一条全新的 recording rule
cat >> "$BASE/rules.yml" <<'EOF'

  # ---- 新增组：用于演示"新增 recording rule 后立刻查不到值" ----
  - name: l4-E-newrecording
    interval: 60s
    rules:
      - record: l4:brandnew:metric
        expr: sum(app_requests_total)
EOF

echo "=== 1) 校验并 reload ==="
docker exec l4-prom /bin/promtool check rules /etc/prometheus/rules.yml 2>&1 | tail -2
curl -s -X POST "$PROM/-/reload"
sleep 2

echo
echo "=== 2) reload 后立刻查新指标（应返回空） ==="
curl -s -G "$PROM/api/v1/query" \
  --data-urlencode 'query=l4:brandnew:metric' \
  | python3 -c "
import json,sys
r = json.load(sys.stdin)['data']['result']
print('  返回 %d 条 %s' % (len(r), '(空！这就是那个坑)' if not r else '(有值)'))
"

echo
echo "=== 3) 该组的求值间隔是 60s，所以要等 <=60s 才有第一个点 ==="
echo "等待 65 秒..."
sleep 65

echo "--- 再查（应有值了） ---"
curl -s -G "$PROM/api/v1/query" \
  --data-urlencode 'query=l4:brandnew:metric' \
  | python3 -c "
import json,sys
r = json.load(sys.stdin)['data']['result']
print('  返回 %d 条' % len(r))
for x in r:
    print('    值=%s' % x['value'][1])
"

echo
echo "=== 4) 另一个坑：源指标消失后，recording rule 的产物会怎样？ ==="
echo "（把 wobble 关掉并停掉应用的 /metrics 之外的路径不影响，这里改为演示查询语法）"
echo "查一个不存在的 recording rule:"
curl -s -G "$PROM/api/v1/query" \
  --data-urlencode 'query=l4:doesnotexist:metric' \
  | python3 -c "
import json,sys
r = json.load(sys.stdin)['data']['result']
print('  返回 %d 条（不存在就是空，不会报错）' % len(r))
"

echo
echo "=== 恢复原规则文件 ==="
mv "$BASE/rules.yml.bak" "$BASE/rules.yml"
curl -s -X POST "$PROM/-/reload"
sleep 2
echo "已恢复并 reload"
