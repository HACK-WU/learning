// 实战篇 C：ACL 生产权限模型 —— agent 配置
//
// 与课 8 的 playground/acl-lab.hcl 的区别：
// 课 8 只演示了「单条只读 policy」，本文件模拟真实的多团队场景，
// 起一个 default_policy = deny 的 agent，所有访问都必须带 token。
//
// 启动：consul agent -dev -config-file=acl-lab.hcl

acl {
  enabled                  = true
  default_policy           = "deny"
  enable_token_persistence = true
  // down_policy 决定「ACL 数据中心不可用时」的兜底行为，默认 extend-cache。
  // 生产上若设 extend-cache，agent 重启前会一直沿用缓存的旧授权，
  // 撤销权限后可能长时间仍生效——这是审计时常见的坑。
  down_policy = "extend-cache"
}
