node_name  = "ops-node-2"
server     = true
datacenter = "opsdc1"
data_dir   = "D:/projects/learning/consul/playground-ops/data/node2"
log_level  = "INFO"

bind_addr      = "127.0.0.1"
advertise_addr = "127.0.0.1"
client_addr    = "127.0.0.1"

bootstrap_expect = 3

ui_config {
  enabled = true
}

ports {
  server   = 9300
  serf_lan = 9311
  serf_wan = 9321
  http     = 9500
  dns      = 9600
  grpc     = 9520
}

retry_join = ["127.0.0.1:8311", "127.0.0.1:10311"]
