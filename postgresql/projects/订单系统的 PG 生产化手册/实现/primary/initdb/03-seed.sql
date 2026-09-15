-- 可重复阅读的教学种子：两个租户、树形分类、客户、商品和 12,000 条订单。
-- 订单规模足以观察计划，但仍适合在 macOS Docker Desktop 上快速重建。

INSERT INTO orders.tenants (tenant_id, tenant_name)
VALUES
    ('00000000-0000-0000-0000-00000000000a', 'tenant-a'),
    ('00000000-0000-0000-0000-00000000000b', 'tenant-b');

INSERT INTO orders.product_categories (category_id, tenant_id, parent_category_id, category_name)
VALUES
    (1, '00000000-0000-0000-0000-00000000000a', NULL, '电子产品'),
    (2, '00000000-0000-0000-0000-00000000000a', 1, '配件'),
    (3, '00000000-0000-0000-0000-00000000000b', NULL, '家居用品'),
    (4, '00000000-0000-0000-0000-00000000000b', 3, '厨房');

INSERT INTO orders.customers (customer_id, tenant_id, email, display_name)
VALUES
    (1, '00000000-0000-0000-0000-00000000000a', 'alice@example.com', 'Alice'),
    (2, '00000000-0000-0000-0000-00000000000a', 'bob@example.com', 'Bob'),
    (3, '00000000-0000-0000-0000-00000000000b', 'carol@example.com', 'Carol'),
    (4, '00000000-0000-0000-0000-00000000000b', 'dave@example.com', 'Dave');

INSERT INTO orders.products (
    product_id, tenant_id, category_id, sku, product_name, price, stock, metadata
)
VALUES
    (101, '00000000-0000-0000-0000-00000000000a', 2, 'A-KEYBOARD', '机械键盘', 299.00, 100, '{"color":"black","tags":["office","input"]}'),
    (102, '00000000-0000-0000-0000-00000000000a', 2, 'A-MOUSE', '无线鼠标', 129.00, 80, '{"color":"white","tags":["office","input"]}'),
    (201, '00000000-0000-0000-0000-00000000000b', 4, 'B-CUP', '保温杯', 89.00, 60, '{"color":"blue","tags":["home","drink"]}'),
    (202, '00000000-0000-0000-0000-00000000000b', 4, 'B-PAN', '不粘锅', 239.00, 40, '{"color":"red","tags":["home","cook"]}');

INSERT INTO orders.orders (
    tenant_id, customer_id, status, total_amount, idempotency_key, created_at
)
VALUES
    ('00000000-0000-0000-0000-00000000000a', 1, 'paid', 299.00, 'seed-fixed-1', clock_timestamp() - interval '2 days'),
    ('00000000-0000-0000-0000-00000000000b', 3, 'shipped', 89.00, 'seed-fixed-2', clock_timestamp() - interval '1 day');

INSERT INTO orders.order_items (order_id, product_id, quantity, unit_price)
SELECT o.order_id, p.product_id, 1, p.price
FROM orders.orders AS o
JOIN orders.products AS p ON p.sku = CASE o.idempotency_key
    WHEN 'seed-fixed-1' THEN 'A-KEYBOARD'
    ELSE 'B-CUP'
END;

INSERT INTO orders.orders (
    tenant_id, customer_id, status, total_amount, idempotency_key, created_at
)
SELECT
    CASE WHEN s % 2 = 0
        THEN '00000000-0000-0000-0000-00000000000a'::uuid
        ELSE '00000000-0000-0000-0000-00000000000b'::uuid
    END,
    CASE WHEN s % 2 = 0 THEN 1 + (s % 2) ELSE 3 + (s % 2) END,
    CASE s % 4 WHEN 0 THEN 'pending' WHEN 1 THEN 'paid' WHEN 2 THEN 'shipped' ELSE 'cancelled' END,
    CASE WHEN s % 2 = 0 THEN 299.00 * (1 + s % 3) ELSE 89.00 * (1 + s % 3) END,
    'seed-bulk-' || s,
    clock_timestamp() - make_interval(mins => s)
FROM generate_series(1, 12000) AS g(s);

INSERT INTO orders.order_items (order_id, product_id, quantity, unit_price)
SELECT
    o.order_id,
    p.product_id,
    1 + (right(o.idempotency_key, length(o.idempotency_key) - 10)::integer % 3),
    p.price
FROM orders.orders AS o
JOIN orders.products AS p
  ON p.sku = CASE WHEN o.tenant_id = '00000000-0000-0000-0000-00000000000a'::uuid
                  THEN 'A-KEYBOARD' ELSE 'B-CUP' END
WHERE o.idempotency_key LIKE 'seed-bulk-%';

INSERT INTO orders.order_events (order_id, event_type, payload)
SELECT order_id, 'order.seeded', jsonb_build_object('source', 'initdb')
FROM orders.orders;

SELECT setval(pg_get_serial_sequence('orders.product_categories', 'category_id'), max(category_id))
FROM orders.product_categories;
SELECT setval(pg_get_serial_sequence('orders.customers', 'customer_id'), max(customer_id))
FROM orders.customers;
SELECT setval(pg_get_serial_sequence('orders.products', 'product_id'), max(product_id))
FROM orders.products;
SELECT setval(pg_get_serial_sequence('orders.orders', 'order_id'), max(order_id))
FROM orders.orders;
SELECT setval(pg_get_serial_sequence('orders.order_events', 'event_id'), max(event_id))
FROM orders.order_events;

REFRESH MATERIALIZED VIEW orders.revenue_by_day;
ANALYZE;
