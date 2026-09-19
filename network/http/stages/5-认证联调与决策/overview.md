# 阶段 5 概览：认证联调与决策

> 所属课程：HTTP 系统学习 ｜ 故事章节：回到日常，收束成决策 ｜ 上一阶段：[阶段 4 · 协议演进](../4-协议演进/overview.md)

> 🔄 **叙事转折**：阶段 4 走完协议纵深后，本阶段回到日常应用层——纵深是为了收束成决策，不是回退。

## 🎯 本阶段目标

- 能处理 Cookie/Session/Token 与 CORS 的日常问题：登录态掉了会查、CORS 报错能定位是谁的配置问题。
- 能独立完成一次从症状到定位的完整排障：用抓包工具看见报文，把问题落到具体一层。
- 输出个人决策清单：缓存配置、协议升级（h2/h3）、认证选型（Session vs JWT）各给一份有依据的决策——故事在此收束。

## 📍 学习重点

- 会话的三条路线：Cookie 是在无状态 HTTP 上"补回状态"的载体，Secure、HttpOnly、SameSite 各防一类攻击，域与路径决定生效范围——课 1 埋的伏笔在此回收。
- Session 与 Token 的取舍：服务端 Session 的有状态本质 vs JWT 的自包含校验；无状态换来扩展性，但注销与续期要付出代价。
- HTTP 认证头：Authorization 携带 Basic/Bearer 凭证，401 与 WWW-Authenticate 的配合——阶段 1 状态码语义的日常用武之地。
- 同源策略与 CORS：源 = 协议+域名+端口，限制的是跨源读取；CORS 是对限制的"受控放宽"而非开关，带凭证时 Allow-Origin 不能为 *。
- 抓包方法论与决策收束：DevTools Network / curl -v / mitmproxy 各管一段；把前四个阶段踩过的坑收束成缓存、协议、认证三张决策树。

## ✅ 必须掌握的知识点

| 知识点 | 所属课 | 学完应能 |
|--------|--------|----------|
| Cookie 机制与安全属性 | 课 13《Cookie、Session 与 Token：让无状态记住你》 | 能说清 Set-Cookie 与浏览器存储的关系、Secure/HttpOnly/SameSite 各防什么、域与路径的生效范围 |
| Session 与 Token 两条路线 | 课 13《Cookie、Session 与 Token：让无状态记住你》 | 能对比服务端 Session 与 JWT 的有状态/无状态取舍，说清无状态的好处与注销、续期的代价 |
| HTTP 认证头 | 课 13《Cookie、Session 与 Token：让无状态记住你》 | 会用 Authorization 头携带 Basic/Bearer 凭证，说清 401 与 WWW-Authenticate 的配合 |
| 同源策略 | 课 14《CORS 与同源策略：浏览器的一票否决》 | 能说清源 = 协议+域名+端口、同源策略限制的是跨源读取，理解 CORS 是"受控放宽"而非开关 |
| CORS 机制 | 课 14《CORS 与同源策略：浏览器的一票否决》 | 能区分简单请求与预检 OPTIONS、读懂 Access-Control-Allow-* 响应头，知道带凭证时 Allow-Origin 不能为 * |
| 高频 CORS 报错排查 | 课 14《CORS 与同源策略：浏览器的一票否决》 | 拿到 'No Access-Control-Allow-Origin' 报错能定位是谁的问题，会按排查顺序处理预检失败与服务端已配仍报错 |
| 抓包方法论 | 课 15《抓包排障与决策清单：课程收束》 | 会按证据目标使用 DevTools Network、用 curl -v 验证直连行为；理解在隔离且获授权的测试环境中用 mitmproxy 看 HTTPS 解密流量 |
| 综合排障推演 | 课 15《抓包排障与决策清单：课程收束》 | 能沿"从症状到定位"的决策树，完整解剖接口慢与登录失效两个案例 |
| 决策清单 | 课 15《抓包排障与决策清单：课程收束》 | 能对缓存配置、协议升级（h2/h3）、认证选型（Session vs JWT）给出有依据的决策 |

## 🗺️ 本阶段路径图

![阶段 5 认证联调与决策路径图](./assets/stage-05-auth-debugging-path.svg)

> SVG 展示本阶段 3 门课、9 个知识点的学习顺序与递进关系：先在无状态协议上维持会话（课 13），再解决跨源场景下凭证怎么带（课 14），最后用抓包把一切收束成决策（课 15）。

## 本阶段产出

- [x] `lessons/lesson-13-Cookie会话与Token.md`
- [x] `lessons/lesson-14-CORS与同源策略.md`
- [x] `lessons/lesson-15-抓包排障与决策清单.md`

> 🏁 本阶段是全课程收官段：课 15 的决策清单直接回扣课程收束目标——"对任意一次 HTTP 请求做解剖，并给出有依据的决策"。阶段知识点与 Phase 3 综合实战均已闭环；下一步可进入 Phase 4 课程手册汇总。
