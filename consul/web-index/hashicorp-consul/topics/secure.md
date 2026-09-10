# 安全基础（ACL 与加密）（Consul Docs · 共 48 条）

> 范围：developer.hashicorp.com/consul/docs/secure · 生成日期：2026-09-10

| 我要… | 去哪一页 | 关键词 | 相关 |
|-------|----------|--------|------|
| 理解 Consul 的威胁模型与安全边界 | [secure/security-model](https://developer.hashicorp.com/consul/docs/secure/security-model) | 安全模型、威胁 | |
| 核心组件的威胁模型细节 | [secure/security-model/core](https://developer.hashicorp.com/consul/docs/secure/security-model/core) | 威胁模型 | |
| 查「安全模型、CTS」的官方说明（用法/配置/注意事项） | [secure/security-model/cts](https://developer.hashicorp.com/consul/docs/secure/security-model/cts) | 安全模型、CTS | |
| 查「加密、最佳实践」的官方说明（用法/配置/注意事项） | [secure/encryption/best-practice](https://developer.hashicorp.com/consul/docs/secure/encryption/best-practice) | 加密、最佳实践 | |
| 查「加密、gossip、启用、existing」的官方说明（用法/配置/注意事项） | [secure/encryption/gossip/enable/existing](https://developer.hashicorp.com/consul/docs/secure/encryption/gossip/enable/existing) | 加密、gossip、启用、existing | |
| 启用 gossip 加密（key 分发） | [secure/encryption/gossip/enable](https://developer.hashicorp.com/consul/docs/secure/encryption/gossip/enable) | gossip、加密 | |
| 查「加密、gossip、rotate、K8s」的官方说明（用法/配置/注意事项） | [secure/encryption/gossip/rotate/k8s](https://developer.hashicorp.com/consul/docs/secure/encryption/gossip/rotate/k8s) | 加密、gossip、rotate、K8s | |
| 轮转 gossip key | [secure/encryption/gossip/rotate/vm](https://developer.hashicorp.com/consul/docs/secure/encryption/gossip/rotate/vm) | gossip、轮转 | |
| 查「加密、TLS、启用、new、openssl」的官方说明（用法/配置/注意事项） | [secure/encryption/tls/enable/new/openssl](https://developer.hashicorp.com/consul/docs/secure/encryption/tls/enable/new/openssl) | 加密、TLS、启用、new、openssl | |
| 新建集群启用 TLS（内置 CA） | [secure/encryption/tls/enable/new/builtin](https://developer.hashicorp.com/consul/docs/secure/encryption/tls/enable/new/builtin) | TLS、内置 CA | |
| 查「加密、TLS、启用、existing、K8s」的官方说明（用法/配置/注意事项） | [secure/encryption/tls/enable/existing/k8s](https://developer.hashicorp.com/consul/docs/secure/encryption/tls/enable/existing/k8s) | 加密、TLS、启用、existing、K8s | |
| 查「加密、TLS、启用、existing、虚机」的官方说明（用法/配置/注意事项） | [secure/encryption/tls/enable/existing/vm](https://developer.hashicorp.com/consul/docs/secure/encryption/tls/enable/existing/vm) | 加密、TLS、启用、existing、虚机 | |
| 查「加密、TLS、rotate、K8s」的官方说明（用法/配置/注意事项） | [secure/encryption/tls/rotate/k8s](https://developer.hashicorp.com/consul/docs/secure/encryption/tls/rotate/k8s) | 加密、TLS、rotate、K8s | |
| 轮转 TLS 证书 | [secure/encryption/tls/rotate/vm](https://developer.hashicorp.com/consul/docs/secure/encryption/tls/rotate/vm) | TLS、轮转 | |
| 配 mTLS（双向验证） | [secure/encryption/tls/mtls](https://developer.hashicorp.com/consul/docs/secure/encryption/tls/mtls) | mTLS | |
| 看加密总览（gossip + TLS 两层） | [secure/encryption](https://developer.hashicorp.com/consul/docs/secure/encryption) | 加密、总览 | |
| 查 ACL 规则语法（service/kv/node 等资源） | [secure/acl/rule](https://developer.hashicorp.com/consul/docs/secure/acl/rule) | rule、语法 | |
| 查「ACL、Sentinel」的官方说明（用法/配置/注意事项） | [secure/acl/sentinel](https://developer.hashicorp.com/consul/docs/secure/acl/sentinel) | ACL、Sentinel | |
| ACL 落地最佳实践 | [secure/acl/best-practice](https://developer.hashicorp.com/consul/docs/secure/acl/best-practice) | ACL、最佳实践 | |
| 查「ACL、token、快照 agent」的官方说明（用法/配置/注意事项） | [secure/acl/token/snapshot-agent](https://developer.hashicorp.com/consul/docs/secure/acl/token/snapshot-agent) | ACL、token、快照 agent | |
| 查「ACL、token、mesh gateway」的官方说明（用法/配置/注意事项） | [secure/acl/token/mesh-gateway](https://developer.hashicorp.com/consul/docs/secure/acl/token/mesh-gateway) | ACL、token、mesh gateway | |
| 查「ACL、token、federation」的官方说明（用法/配置/注意事项） | [secure/acl/token/federation](https://developer.hashicorp.com/consul/docs/secure/acl/token/federation) | ACL、token、federation | |
| 查「ACL、token、Agent」的官方说明（用法/配置/注意事项） | [secure/acl/token/agent](https://developer.hashicorp.com/consul/docs/secure/acl/token/agent) | ACL、token、Agent | |
| 查「ACL、token、vault-backend」的官方说明（用法/配置/注意事项） | [secure/acl/token/vault-backend](https://developer.hashicorp.com/consul/docs/secure/acl/token/vault-backend) | ACL、token、vault-backend | |
| 查「ACL、token、terminating-gateway」的官方说明（用法/配置/注意事项） | [secure/acl/token/terminating-gateway](https://developer.hashicorp.com/consul/docs/secure/acl/token/terminating-gateway) | ACL、token、terminating-gateway | |
| 查「ACL、token、ingress-gateway」的官方说明（用法/配置/注意事项） | [secure/acl/token/ingress-gateway](https://developer.hashicorp.com/consul/docs/secure/acl/token/ingress-gateway) | ACL、token、ingress-gateway | |
| 查「ACL、token、DNS」的官方说明（用法/配置/注意事项） | [secure/acl/token/dns](https://developer.hashicorp.com/consul/docs/secure/acl/token/dns) | ACL、token、DNS | |
| 查「ACL、token、服务」的官方说明（用法/配置/注意事项） | [secure/acl/token/service](https://developer.hashicorp.com/consul/docs/secure/acl/token/service) | ACL、token、服务 | |
| 查「ACL、token、ESM（外部服务监控）」的官方说明（用法/配置/注意事项） | [secure/acl/token/esm](https://developer.hashicorp.com/consul/docs/secure/acl/token/esm) | ACL、token、ESM（外部服务监控） | |
| ACL token 的生成/管理与特殊 token 一览 | [secure/acl/token](https://developer.hashicorp.com/consul/docs/secure/acl/token) | token、凭证 | |
| 查「ACL、token、replication」的官方说明（用法/配置/注意事项） | [secure/acl/token/replication](https://developer.hashicorp.com/consul/docs/secure/acl/token/replication) | ACL、token、replication | |
| 查「ACL、token、Web UI」的官方说明（用法/配置/注意事项） | [secure/acl/token/ui](https://developer.hashicorp.com/consul/docs/secure/acl/token/ui) | ACL、token、Web UI | |
| ACL 权限不通时排查（Permission denied 类） | [secure/acl/troubleshoot](https://developer.hashicorp.com/consul/docs/secure/acl/troubleshoot) | ACL、排障 | |
| 用 role 组合 policy 授权 | [secure/acl/role](https://developer.hashicorp.com/consul/docs/secure/acl/role) | role、角色 | |
| 用 K8s ServiceAccount 换 Consul token | [secure/acl/auth-method/k8s](https://developer.hashicorp.com/consul/docs/secure/acl/auth-method/k8s) | K8s、SA、认证 | |
| 用 OIDC 做 SSO 登录 UI/API | [secure/acl/auth-method/oidc](https://developer.hashicorp.com/consul/docs/secure/acl/auth-method/oidc) | OIDC、SSO | |
| 用 JWT 做认证 | [secure/acl/auth-method/jwt](https://developer.hashicorp.com/consul/docs/secure/acl/auth-method/jwt) | JWT、认证 | |
| 用 AWS IAM 做认证 | [secure/acl/auth-method/aws](https://developer.hashicorp.com/consul/docs/secure/acl/auth-method/aws) | AWS、IAM | |
| 用 auth-method 对接外部身份（K8s/OIDC/JWT/AWS） | [secure/acl/auth-method](https://developer.hashicorp.com/consul/docs/secure/acl/auth-method) | auth-method、外部认证 | |
| 理解 legacy ACL（旧版白名单）与迁移 | [secure/acl/legacy](https://developer.hashicorp.com/consul/docs/secure/acl/legacy) | legacy、迁移 | |
| 查「ACL、重置」的官方说明（用法/配置/注意事项） | [secure/acl/reset](https://developer.hashicorp.com/consul/docs/secure/acl/reset) | ACL、重置 | |
| 理解 ACL 体系（token/policy/role 怎么协作） | [secure/acl](https://developer.hashicorp.com/consul/docs/secure/acl) | ACL、权限 | |
| 查「ACL、Vault、虚机」的官方说明（用法/配置/注意事项） | [secure/acl/vault/vm](https://developer.hashicorp.com/consul/docs/secure/acl/vault/vm) | ACL、Vault、虚机 | |
| 引导 ACL（拿第一个 management token） | [secure/acl/bootstrap](https://developer.hashicorp.com/consul/docs/secure/acl/bootstrap) | ACL、bootstrap | |
| 写 ACL policy（规则语法） | [secure/acl/policy](https://developer.hashicorp.com/consul/docs/secure/acl/policy) | policy、规则 | |
| 接 Auth0 做 SSO 的完整示例 | [secure/sso/auth0](https://developer.hashicorp.com/consul/docs/secure/sso/auth0) | SSO、Auth0 | |
| 查「auto-config、Docker」的官方说明（用法/配置/注意事项） | [secure/auto-config/docker](https://developer.hashicorp.com/consul/docs/secure/auto-config/docker) | auto-config、Docker | |
| 看安全总览（ACL+加密+模型） | [secure](https://developer.hashicorp.com/consul/docs/secure) | 安全、总览 | |
