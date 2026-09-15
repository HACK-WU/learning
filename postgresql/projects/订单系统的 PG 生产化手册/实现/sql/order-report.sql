-- 订单列表、分类树、窗口排名与 JSONB 查询。
\echo '=== 最近订单：键集分页 ==='
SELECT order_id, tenant_id, status, total_amount, created_at
FROM orders.orders
WHERE tenant_id = '00000000-0000-0000-0000-00000000000a'
  AND (created_at, order_id) < (clock_timestamp(), 9223372036854775807)
ORDER BY created_at DESC, order_id DESC
LIMIT 10;

\echo '=== 租户 GMV 排名：窗口函数 ==='
SELECT tenant_id, customer_id, gmv, gmv_rank
FROM orders.top_customers
ORDER BY tenant_id, gmv_rank, customer_id
LIMIT 10;

\echo '=== 分类树：递归 CTE ==='
WITH RECURSIVE category_tree AS (
    SELECT category_id, parent_category_id, category_name, 0 AS depth,
           category_name::text AS path
    FROM orders.product_categories
    WHERE parent_category_id IS NULL
    UNION ALL
    SELECT child.category_id, child.parent_category_id, child.category_name,
           parent.depth + 1, parent.path || ' / ' || child.category_name
    FROM orders.product_categories AS child
    JOIN category_tree AS parent
      ON child.parent_category_id = parent.category_id
)
SELECT repeat('  ', depth) || path AS category_path
FROM category_tree
ORDER BY category_id;

\echo '=== JSONB 标签包含 ==='
SELECT tenant_id, sku, product_name
FROM orders.products
WHERE metadata @> '{"tags":["office"]}'::jsonb;
