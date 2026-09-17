// web 团队：管自己的服务与自己的 KV，共享前缀只读，其他一律不给
//
// 关键设计（最小权限原则）：
// 1. 只给 key_prefix "web/" 的 write，不给 "" —— 否则能读全库 KV
// 2. 只给 service_prefix "web" 的 write，不给 "" —— 否则能顶掉别人的服务
// 3. node_prefix "" read 是必需的：看不到节点就看不到任何健康检查结果
//    （课 8 实测：只给 service:read + node:read 才能通过 HTTP 查到服务）
// 4. service_prefix "" read 让 web 能"发现"别人（只读），但不能"改"别人

key_prefix "web/" {
  policy = "write"
}

key_prefix "shared/" {
  policy = "read"
}

service_prefix "web" {
  policy = "write"
}

service_prefix "" {
  policy = "read"
}

node_prefix "" {
  policy = "read"
}
