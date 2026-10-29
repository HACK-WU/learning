"""身份声明。

这个项目的关键设计点：user 层记忆与 principal 都依赖已验证身份。

实测约束（本机 0.9.5）：
  - Slack 通道属于 ingress trigger，**必须有根级 identity.{py,ts}**，
    不能退回部署服务身份 —— 删掉本文件后 `mda dev` 直接报：
    "channels/ or connectors/ with an ingress trigger ... require a root identity declaration;
     ingress triggers cannot fall back to a deployment service principal"
  - 想让 user 层记忆真正生效，auth 不能留默认 LangSmith API key 模式
    （那个模式没有"人"的概念，user 层会一直空着）

部署前把 project_ref 换成你的 Supabase 项目，并在 .env 里配好 SUPABASE_URL / SUPABASE_ANON_KEY。
本地只想跑 agent 逻辑、不验身份时，可临时改成 auth="backend"（backend 自行校验请求头）。
"""

from managed_deepagents import auth, define_identity

identity = define_identity(
    auth=auth.supabase(project_ref="your-project-ref"),
)
