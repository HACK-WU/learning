consul {
  address = "127.0.0.1:8500"
}
template {
  source      = "D:/projects/learning/consul/playground/gateway.tpl"
  destination = "D:/projects/learning/consul/playground/gateway.conf"
  exec {
    command = ["cmd", "/c", "D:/projects/learning/consul/playground/reload.cmd"]
  }
}
