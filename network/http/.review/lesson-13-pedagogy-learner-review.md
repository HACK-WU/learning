# 课 13《Cookie、Session 与 Token：让无状态记住你》评审记录

> 评审日期：2026-09-16
> 评审方式：主 agent 内联完成 pedagogy + learner 两轮评审；`course-reviewer` 子 agent 尚未创建，因此独立性受限。以下 learner 结论基于学习者代入推理，非真实用户测试。
> 评审对象：课文、4 张课级 SVG、Python 标准库机制实验、独立应用实战文件及 2 张分步设计 SVG。

## 结论

| 级别 | 数量 | 结论 |
|---|---:|---|
| P0 | 0 | 无事实错误、敏感信息、断链或会把读者带入错误认证实践的内容 |
| P1 | 0 | 入口图、地图、知识点六要素、图后读图指引、应用实战入口与分步图、命令速查卡和双视角评审齐备 |
| P2 | 0 | 无需延后处理的表达或排版问题 |

**结论：通过，可交付并勾选 `00-评审清单.md` 的阶段 5·课 13 条目。**

## 写前与事实核查记录

| 事实 / 结论 | 核查来源 | 结果 |
|---|---|---|
| HTTP 是无状态应用层协议 | [RFC 9110 §1](https://www.rfc-editor.org/rfc/rfc9110.html#section-1) | PASS；正文第 17 行标 `（核查于 2026-09）` |
| `Set-Cookie` 由服务端发送，用户代理保存后在匹配范围内用 `Cookie` 回传；回传头不带原属性 | [RFC 6265 §4.1–§4.2](https://www.rfc-editor.org/rfc/rfc6265.html)、[MDN Cookies](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Cookies) | PASS；正文第 82–118 行并列响应 / 请求方向与生命周期 |
| `Secure`、`HttpOnly`、`Domain`、`Path` 的边界；`Path` 不是安全边界 | [RFC 6265](https://www.rfc-editor.org/rfc/rfc6265.html)、[MDN Set-Cookie](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Set-Cookie) | PASS；正文第 108–118 行未把任一属性写成万能防护 |
| `SameSite=None` 需要 `Secure`；未显式设置时浏览器默认行为不应被当作跨浏览器常量 | [MDN Set-Cookie](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Set-Cookie)、[MDN Cookies](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Cookies) | PASS；正文第 114 行明确要求现场核对默认行为 |
| JWT Claims Set 是 JSON 对象，可由 JWS 签名 / MAC 或由 JWE 加密；签名 JWT 不自动提供保密性 | [RFC 7519 §3、§7](https://www.rfc-editor.org/rfc/rfc7519.html) | PASS；正文第 178–239 行区分 JWS/JWE、解码与可信校验 |
| `Authorization` 携带凭证；401 表示缺少有效认证凭证且必须带 `WWW-Authenticate`；403 是认证通过但拒绝访问的边界 | [RFC 9110 §11.3、§11.6、§15.5.2、§15.5.4](https://www.rfc-editor.org/rfc/rfc9110.html)、[MDN HTTP authentication](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Authentication) | PASS；正文第 305–359 行、课后小测参考答案落地 |
| Basic 是 Base64 编码的用户名 / 密码，不能替代 TLS | [RFC 7617 §1](https://www.rfc-editor.org/rfc/rfc7617.html) | PASS；正文第 321–328 行明确“编码，不是加密” |
| Bearer 是认证方案，不是 JWT 的别名；缺少有效凭证时的 Bearer 质询与 scope 不足的 403 边界 | [RFC 6750 §3](https://www.rfc-editor.org/rfc/rfc6750.html) | PASS；正文第 330–359 行和术语对照表区分方案 / 格式 |
| 会话 ID、生命周期和失效策略的安全实践 | [MDN Session management](https://developer.mozilla.org/en-US/docs/Web/Security/Authentication/Session_management)、[OWASP Session Management Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Session_Management_Cheat_Sheet.html) | PASS；应用实战第 13–135 行只做教学示意并标注未上生产 |

## Pedagogy 视角（教学法）

| 维度 | 具体锚点 | 评审观察 | 结论 |
|---|---|---|---|
| 结构与故事弧 | 课文第 15–25、29–41、410–459 行 | 从“登录返回 200 但 `/orders` 仍未登录”进入，第二幕把凭证载体 / 状态归属 / 认证状态码冲突摆出来，第四幕用同一链路实测，第五幕收束为三层判断 | PASS；五幕闭环 |
| 入口与认知降载 | 第 21–25、47–63 行；`cookie-session-token-global-overview.svg` | 一句话本质不放 Cookie / Session / Token 术语；处境对照有“后续请求是否出现头部、无凭证是否 401、注销后是否仍可访问”的观测锚点；一眼图仅用小卡 / 记录 / 声明表达三种保存位置；地图只列三步 | PASS；L7 无 P0/P1 |
| 递进与承接 | 第 65–68、169–172、286–289 行 | 13.1 先解决浏览器能否自动携带，13.2 回答凭证由谁解释，13.3 最后把凭证放进 API 标准头；每点都有 `🧭 第 N/3 步`，不是平铺三种方案 | PASS |
| 图表选型 | 4 张课级 SVG + 13.3 第 305–319 行 Mermaid；实战 2 张分步 SVG | Cookie 属性是多概念 / 范围对比，Session/Token 是状态归属对比，课末是三层分类，均使用 SVG；认证质询是时序，使用 Mermaid；每张图后都有读图指引 | PASS；无 C 类退回 Mermaid |
| 六要素完整性 | 13.1 第 70–168、13.2 第 174–284、13.3 第 291–406 行 | 三个知识点均有一句话定义、类比、类比边界、核心原理、示例演示、常见误区、一句话记住、行话对照、官方文档；多路线均有四列策略对照表 | PASS |
| 术语双轨 | 第 53、72、99–106、174、187–239、291、305–359 行 | 先用小卡 / 寄存柜票根 / 通行证 / 办公楼建立直觉，再回指 Cookie、Session、Token、JWT、Basic、Bearer；行话表给出标准叫法与遇到位置，未把 Bearer 冒充 JWT | PASS |
| 实操边界 | 第 414–449 行；实验脚本第 1–153 行；实战第 1–141 行 | 实验明确是回环临时服务与状态模型，不假装完成真实 JWT 加密 / 验签；应用实战明确“会用、不上生产”，把用户目录、密码哈希、密钥托管等超纲内容列为全貌边界 | PASS |
| 决策可执行性 | 第 218–239、341–359、443–449 行；实战第 70–135 行 | 不只说 Session / Token 优缺点，而是落到多实例共享、立即注销、权限变化、Bearer 质询和状态码分支；独立实战由基础内存会话演进到共享存储 + ID 轮换 | PASS |
| 节奏与非模板亮点 | 第 31–39、108–118、240–256、414–443 行 | 真假直觉对照、属性三列反边界表、注销差异小表、真实本地输出交错出现；无连续四个以上纯文字段落；实验初跑发现并修正了响应头名称大小写读取问题，最终输出与课文一致 | PASS；L8 无 P1 |

## Learner 视角（学习者代入）

以下按 L1–L8 逐项走读；结论是学习者代入推理，非真实用户测试。

| 维度 | 走读锚点 | 学习者体验与正面发现 | 结论 |
|---|---|---|---|
| L1 场景吸引力 | 第 17–25 行 | 第一幕先写“登录 200、下一页未登录”，再抛出“由谁记住、记住什么、如何证明没改过”，场景直接对应日常联调，不以 Cookie 定义开场 | PASS；无 P0/P1 |
| L2 由浅入深 | 第 29–63 → 65–168 → 169–284 → 286–406 行 | 先提出“登录凭证放哪”，再拆浏览器规则，再拆服务端记录 / 自包含声明，最后落到认证头和状态码；JWT 的 JWS/JWE 细节放在 Session/Token 直觉之后 | PASS |
| L3 认知阶梯 | 第 74–78、178–181、295–303 行 | 编号卡、寄存柜票根、带防伪章的通行证和办公楼类比先行；每个类比都紧跟“边界”，避免把 Cookie 当认证、把签名当加密、把 401 当权限不足 | PASS |
| L4 故事弧 | 第 19、31–41、414–443、461–483 行 | 小航的登录故障在第二幕转为三个知识点，第四幕输出直接验证同一故障，课末四问和小测重新回到“下一请求能否被识别” | PASS |
| L5 困惑点与顿悟 | 第 108–118、120–128、218–239、341–359 行 | 最容易混淆的“属性是不是安全开关”“JWT 是否加密”“Bearer 是否等于 JWT”“401 / 403 谁代表什么”均在首次正式解释附近就给出边界；`Cookie 是载体，Session / Token 是状态组织`是全课关键顿悟句 | PASS |
| L6 全局定位 | 第 453–466、504–509 行 | 能把本课接到课 3 的状态码、课 5/6 的 HTTPS / 证书和下一课的同源 / CORS；接力提示词明确指向课 14，并给出原因入口 | PASS |
| L7 入口可读性 | 第 21–25、47–63 行与全局 SVG | 本质、处境对照、零术语全局图、读图指引和三步地图都在第一个知识点前；图上没有 Cookie、Session、Token、JWT、HTTP 等本课术语 | PASS；无 P0/P1 |
| L8 节奏与密度 | 第 35–39、104–118、240–256、414–443 行 | 反直觉表、属性对照表、Session/Token 注销表和本地实验输出形成节奏变化；应用实战再用两张“比上一版多了什么”的设计图提供非模板化演进 | PASS |

## 应用实战代码正确性 review（主 agent 直接静态审查）

| 检查项 | 结果 |
|---|---|
| 基础实现是否生成不可预测的会话 ID、记录过期时间并通过 Cookie 属性传递 | PASS；实战第 32–55 行使用 `secrets.token_urlsafe(32)`、UTC 过期时间和 `Secure` / `HttpOnly` / `SameSite=Lax` |
| 基础实现是否把密码明文比较或写入凭证 | PASS；第 43 行明确省略密码校验并要求使用密码哈希；没有真实密码或凭证 |
| 综合实现是否解决多实例共享与会话固定的基础问题 | PASS；第 91–104 行写入 `shared_store`、设置 TTL、删除旧 ID；第 78–80 行分步图明确新增内容 |
| Bearer 分支是否把 JWT 验证交给已审计库，并保留 401 质询 | PASS；第 107–120 行通过注入的 `access_token_verifier` 验证并返回 `WWW-Authenticate`；没有手写伪验签 |
| 注销是否同时清除服务端记录与浏览器副本 | PASS；第 123–128 行删除服务端会话并用同名、同路径 Cookie `max_age=0` 清理浏览器副本 |
| 本地机制实验是否真的验证课文输出 | PASS；脚本用标准库 `CookieJar`、临时回环服务和大小写不敏感响应头读取，实际输出与正文第 422–438 行一致 |

## 交付前机械检查

- [x] 课文 519 行；五幕、知识点导航、三点承接、六要素、课末总结、命令速查卡、4 题小测、接力提示词、课程导航齐备
- [x] 4 张课级 SVG 与 2 张应用实战分步 SVG 均为独立文件、浅底深字、XML 解析通过；一眼全局图无本课术语
- [x] 教学脚本 `python3 -m py_compile network/http/stages/5-认证联调与决策/labs/lesson-13-cookie-session-token-lab.py` 通过；`--section all` 真实跑通 Cookie 200、无 Cookie 401、Bearer 200 与 `WWW-Authenticate`
- [x] 课文、应用实战、课程目录和应用实战索引的目标本地链接逐条检查，全部存在
- [x] 敏感信息扫描：无真实 token / API key / 密码 / 私钥 / 非公开 URL / 真实内网地址；示例凭证均为显式教学占位文本
- [x] 应用实战判定三问均通过：登录态是现实任务；可从内存 Session 演进到共享 Session / Bearer 校验；没有展开大量课外知识；实战正文控制在单课篇幅约 1/3 内
- [x] 课内 4.2 只保留入口块，正文独立落在 `应用实战/13-Cookie会话与Token.md`；INDEX 已同步

## 评审处置

本批无待修复问题。评审后已完成：

1. `00-学习档案.md`：13.1–13.3 标记已完成，补录事实核查与本评审记录。
2. `00-评审清单.md`：勾选阶段 5·课 13（含应用实战）。
3. `02-课程目录.md`：课 13 改为可点击链接，新增应用实战入口。
4. 阶段 5 `overview.md`、`01-学习路径总览.md` 与仓库根 `AGENTS.md`：课 13 交付、阶段 5 进度 3/9、下一批切换为课 14。
