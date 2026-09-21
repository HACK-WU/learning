node_name  = "ops-node-3"
server     = true
datacenter = "opsdc1"
data_dir   = "D:/projects/learning/consul/playground-ops/data/node3"
log_level  = "INFO"

bind_addr      = "127.0.0.1"
advertise_addr = "127.0.0.1"
client_addr    = "127.0.0.1"

bootstrap_expect = 3

ui_config {
  enabled = true
}

ports {
  server   = 10300
  serf_lan = 10311
  serf_wan = 10321
  http     = 10500
  dns      = 10600
  grpc     = 10520
}

retry_join = ["127.0.0.1:8311", "127.0.0.1:9311"]
