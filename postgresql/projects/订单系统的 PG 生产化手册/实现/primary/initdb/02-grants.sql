-- 先收紧 public，再按职责授权；权限链是 pg_hba → schema USAGE → 对象权限 → RLS。
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON DATABASE order_service FROM PUBLIC;
GRANT CONNECT ON DATABASE order_service TO app_runtime, report_reader, tenant_a_app, tenant_b_app;

GRANT USAGE ON SCHEMA orders TO app_runtime, report_reader, tenant_a_app, tenant_b_app;

GRANT SELECT ON orders.products, orders.customers TO app_runtime;
GRANT EXECUTE ON FUNCTION orders.place_order(uuid, bigint, bigint, integer, text) TO app_runtime;
GRANT EXECUTE ON FUNCTION orders.reserve_stock(bigint, integer) TO app_runtime;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA orders TO app_runtime;

GRANT SELECT ON orders.order_summary, orders.top_customers, orders.low_stock,
    orders.revenue_by_day TO report_reader;

GRANT SELECT, INSERT, UPDATE ON orders.orders TO tenant_a_app, tenant_b_app;
GRANT SELECT ON orders.order_items, orders.products, orders.customers TO tenant_a_app, tenant_b_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA orders TO tenant_a_app, tenant_b_app;

CREATE POLICY tenant_a_orders ON orders.orders
    FOR ALL TO tenant_a_app
    USING (tenant_id = '00000000-0000-0000-0000-00000000000a'::uuid)
    WITH CHECK (tenant_id = '00000000-0000-0000-0000-00000000000a'::uuid);

CREATE POLICY tenant_b_orders ON orders.orders
    FOR ALL TO tenant_b_app
    USING (tenant_id = '00000000-0000-0000-0000-00000000000b'::uuid)
    WITH CHECK (tenant_id = '00000000-0000-0000-0000-00000000000b'::uuid);

ALTER DEFAULT PRIVILEGES IN SCHEMA orders REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA orders REVOKE ALL ON TABLES FROM PUBLIC;
