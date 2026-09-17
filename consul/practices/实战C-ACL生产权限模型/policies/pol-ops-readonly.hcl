// 运维（SRE）：值班账号 —— 排查够用，但不能改业务数据
//
// ⚠️ 关键语法点（2026-09-17 实测踩坑，Consul 2.0.2）：
// operator 资源【不带 label】，正确写法是 operator = "read"，
// 不是 operator_prefix "" { policy = "read" }。
// 后者是无效语法，不会报错，但权限【静默不生效】——
// 配置了半天以为有权限，读 /v1/operator/raft/configuration 照样 403，
// 且 403 原文只说 "lacks permission 'operator:read'"，不告诉你规则写错了。
//
// 同样不带 label 的资源还有：acl、keyring、mesh、peering。
// 只有 key/node/service/session/agent/event/query 才带 label（用 _prefix 形式）。
//
// 实测结果（带本策略的 token）：
//   200: /v1/status/leader, /v1/status/peers, /v1/catalog/nodes,
//        /v1/catalog/services, /v1/agent/members, /v1/agent/self,
//        /v1/operator/raft/configuration, /v1/operator/autopilot/configuration,
//        /v1/agent/metrics
//   403: /v1/acl/tokens（要 acl = "read" 才能看 token 列表）

key_prefix "" {
  policy = "read"
}

service_prefix "" {
  policy = "read"
}

node_prefix "" {
  policy = "read"
}

// ✅ 正确写法：operator 不带 label
operator = "read"

agent_prefix "" {
  policy = "read"
}
