#!/bin/bash
ES="https://localhost:9200"
PW="ESlearn2026"
C="curl.exe -s -k -u elastic:$PW"

echo "===== 确认 ES|QL 中文列名报错的确切位置 ====="
echo ""
echo "--- 用 l8_orders_v2（讲义正文用的索引）---"
$C -X POST "$ES/_query?format=txt" -H "Content-Type: application/json" -d '{
  "query":"FROM l8_orders_v2 | STATS 订单数 = COUNT(*) BY brand"}'
echo ""
echo "--- 用 l8_orders（讲义开场提到的旧索引）---"
$C -X POST "$ES/_query?format=txt" -H "Content-Type: application/json" -d '{
  "query":"FROM l8_orders | STATS 订单数 = COUNT(*) BY brand"}'
echo ""
echo "--- 逐字符定位检查 ---"
python -c "
q1='FROM l8_orders_v2 | STATS 订单数 = COUNT(*) BY brand'
q2='FROM l8_orders | STATS 订单数 = COUNT(*) BY brand'
for name,q in [('l8_orders_v2',q1),('l8_orders',q2)]:
    idx=q.find('订')
    print('  %s: 「订」在第 %s 个字符（0基），报错应报 %s'%(name,idx,idx+1))"
echo ""
echo "===== 确认退款率精确值 ====="
python -c "
print('  4/24 =', 4/24*100)
print('  一位小数:', round(4/24*100,1))
print('  两位小数:', round(4/24*100,2))"
echo ""
echo "===== 确认 stats 的 sum 是 price 还是 amount ====="
echo "  讲义写: stats 一次返回 count=24 min=1999.0 max=12999.0 avg=6527.71 sum=156665.0"
python -c "
prices=[7999,6999,4999,12999,8999,5999,4799,3299,2599,5999,5488,2999,8999,6499,4299,8999,5199,1999,9999,7999,5999,10999,7499,4999]
print('  手算 price 之和:',sum(prices))
print('  而 amount 之和: 190057 (不同！)')
print('  → 确认 stats 作用于 price 字段，讲义正确')"
echo ""
echo "########## DONE-L8-15 ##########"
