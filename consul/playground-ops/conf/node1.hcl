node_name  = "ops-node-1"
server     = true
datacenter = "opsdc1"
data_dir   = "D:/projects/learning/consul/playground-ops/data/node1"
log_level  = "INFO"

bind_addr      = "127.0.0.1"
advertise_addr = "127.0.0.1"
client_addr    = "127.0.0.1"

bootstrap_expect = 3

ui_config {
  enabled = true
}

ports {
  server   = 8300
  serf_lan = 8311
  serf_wan = 8321
  http     = 8500
  dns      = 8600
  grpc     = 8520
}

retry_join = ["127.0.0.1:9311", "127.0.0.1:10311"]
