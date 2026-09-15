-- 先观察，不凭感觉加索引；小表上优化器可能选择 Seq Scan，这是正常的成本决策。
EXPLAIN (ANALYZE, BUFFERS, SETTINGS, COSTS OFF)
SELECT order_id, status, total_amount, created_at
FROM orders.orders
WHERE tenant_id = '00000000-0000-0000-0000-00000000000a'
  AND created_at >= clock_timestamp() - interval '1 day'
ORDER BY created_at DESC, order_id DESC
LIMIT 20;

-- 关闭顺序扫描只用于证明索引可用，不是生产配置。
BEGIN;
SET LOCAL enable_seqscan = off;
EXPLAIN (COSTS OFF)
SELECT order_id, status, total_amount, created_at
FROM orders.orders
WHERE tenant_id = '00000000-0000-0000-0000-00000000000a'
  AND created_at >= clock_timestamp() - interval '1 day'
ORDER BY created_at DESC, order_id DESC
LIMIT 20;
ROLLBACK;
