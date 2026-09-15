CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD :'replication_password';
CREATE ROLE app_runtime LOGIN PASSWORD :'app_password' NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE ROLE report_reader LOGIN PASSWORD :'report_password' NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE ROLE tenant_a_app LOGIN PASSWORD :'tenant_password' NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE ROLE tenant_b_app LOGIN PASSWORD :'tenant_password' NOSUPERUSER NOCREATEDB NOCREATEROLE;

SELECT pg_create_physical_replication_slot('capstone_standby')
WHERE NOT EXISTS (
  SELECT 1
  FROM pg_replication_slots
  WHERE slot_name = 'capstone_standby'
);
