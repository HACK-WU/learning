// api 团队：与 web 团队结构完全对称，只有前缀不同。
//
// 这样设计是为了验证一件事：
// web 的 token 去写 api/ 的 key、去注册名为 api 的服务，必须被拒。
// 两个团队互不知情、互不可改——这才是"多团队共用一套 Consul"的安全边界。

key_prefix "api/" {
  policy = "write"
}

key_prefix "shared/" {
  policy = "read"
}

service_prefix "api" {
  policy = "write"
}

service_prefix "" {
  policy = "read"
}

node_prefix "" {
  policy = "read"
}
