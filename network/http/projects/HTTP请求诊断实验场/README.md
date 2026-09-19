# HTTP 请求诊断实验场

> 一句话需求：给一个正在联调的订单 API 制造几类可观测故障，让学习者从“页面慢 / 登录失效 / 跨源失败 / 重复下载”出发，采集证据、定位层次、选择修复并保留回滚出口。

这是 HTTP 课程的 Phase 3 结课验证项目，不是生产 Web 框架教程。它把前面五个阶段串成一条工作流：

```text
复现症状 → 记录请求/响应 → 拆分耗时 → 判断协议语义 → 选择修复 → 复测 → 写证据卡
```

![项目证据流：从症状到决策](assets/project-evidence-flow.svg)

## 你要完成什么

运行本地实验场，观察并解释四个病例：

1. **慢请求**：302 重定向、首字节延迟、正文分段读取分别留下什么证据？
2. **登录失效**：缺凭证、凭证错误、凭证正确为什么应该分别是 401、403、200？
3. **跨源与缓存**：预检为什么被拒绝？`ETag` 为什么能把第二次响应变成 304？带 hash 的静态资源为什么可以长期缓存？
4. **协议决策**：本地 HTTP/1.1 基线已经能工作时，什么证据足以支持 HTTP/2 或 HTTP/3 升级？

每个病例都要求写出一张证据卡，而不是只写“问题已解决”：

| 字段 | 要留下什么 |
|---|---|
| 现象 | 用户看到什么，能否稳定复现 |
| 请求 | 方法、URL、关键请求头、来源/凭证是否存在 |
| 响应 | 状态码、关键响应头、正文大小 |
| 时间与协议 | 连接、TTFB、正文读取、总耗时、实际协商版本 |
| 假设 | 当前最可能的层和理由 |
| 动作 | 修复、降级或暂不改动什么 |
| 验证与回滚 | 如何确认有效，失败如何撤回 |

## 运行方式

项目只使用 Python 标准库。先确认当前仓库没有项目专用的 Python lockfile 或虚拟环境；本项目无第三方依赖，因此直接使用系统已有的 `python3` 即可，不执行安装命令。

在仓库根目录运行：

```bash
python3 'network/http/projects/HTTP请求诊断实验场/实现/run_cases.py'
```

也可以逐个病例运行：

```bash
python3 'network/http/projects/HTTP请求诊断实验场/实现/run_cases.py' --case slow
python3 'network/http/projects/HTTP请求诊断实验场/实现/run_cases.py' --case auth
python3 'network/http/projects/HTTP请求诊断实验场/实现/run_cases.py' --case cors-cache
python3 'network/http/projects/HTTP请求诊断实验场/实现/run_cases.py' --case protocol
```

运行回归测试：

```bash
python3 -m unittest discover -s 'network/http/projects/HTTP请求诊断实验场/实现' -p 'test_*.py' -v
```

如果想用浏览器或 curl 观察同一个服务：

```bash
python3 'network/http/projects/HTTP请求诊断实验场/实现/server.py' --port 8765
curl -i 'http://127.0.0.1:8765/api/redirect'
curl -sS -o /dev/null -w 'http=%{http_code} ttfb=%{time_starttransfer}s total=%{time_total}s\n' 'http://127.0.0.1:8765/api/slow'
curl -i 'http://127.0.0.1:8765/api/auth'
curl -i 'http://127.0.0.1:8765/api/auth' -H 'Authorization: Bearer <DEMO_TOKEN>'
curl -i 'http://127.0.0.1:8765/api/orders'
```

浏览器观察时打开 DevTools → Network，勾选 Preserve log，然后访问 `http://127.0.0.1:8765/`；选中请求查看 Headers、Timing、Response，并只在脱敏后导出 HAR 或 Copy as cURL。

## 覆盖知识点地图

下表只把项目真正使用或作出决策回顾的知识点列为“覆盖”，没有把没有实现的协议细节硬贴到代码上。代码证据与设计证据分开标注。

| 知识点 | 所属课 | 项目证据 |
|---|---|---|
| 2.1 报文四段结构 | [课 2](../../stages/1-报文与语义/lessons/lesson-02-报文解剖.md) | `server.py` 统一生成状态行、头部、正文和长度 |
| 2.2 高频头部速览 | [课 2](../../stages/1-报文与语义/lessons/lesson-02-报文解剖.md) | `Location`、`ETag`、`Authorization`、`Origin`、`Content-Length` |
| 3.2 状态码五大类 | [课 3](../../stages/1-报文与语义/lessons/lesson-03-方法与状态码.md) | 200、201、204、302、304、401、403、404 分支 |
| 3.3 重定向 3xx | [课 3](../../stages/1-报文与语义/lessons/lesson-03-方法与状态码.md) | `/api/redirect` 的 302 与 `Location` |
| 4.1 TCP 连接建立成本 | [课 4](../../stages/2-连接与安全/lessons/lesson-04-连接管理与队头阻塞.md) | `client.py` 记录 connect 与总耗时 |
| 4.2 Keep-Alive 与连接复用 | [课 4](../../stages/2-连接与安全/lessons/lesson-04-连接管理与队头阻塞.md) | `Content-Length` 保证响应边界；设计决策说明本项目客户端为何每次独立连接 |
| 5.1 明文传输威胁 | [课 5](../../stages/2-连接与安全/lessons/lesson-05-HTTPS加密原理.md) | 设计决策记录“诊断数据不出本机、真实凭证不入仓库” |
| 6.2 证书校验失败 | [课 6](../../stages/2-连接与安全/lessons/lesson-06-证书与信任.md) | 协议决策保留 HTTPS 证书校验/代理信任检查清单 |
| 7.2 协商缓存 | [课 7](../../stages/3-缓存与性能/lessons/lesson-07-HTTP缓存.md) | `ETag` + `If-None-Match` → 304 |
| 7.3 缓存决策实战 | [课 7](../../stages/3-缓存与性能/lessons/lesson-07-HTTP缓存.md) | HTML/API `no-cache` 与 fingerprinted asset `immutable` 对照 |
| 8.2 性能测量 | [课 8](../../stages/3-缓存与性能/lessons/lesson-08-性能测量与优化.md) | connect、TTFB、body drain、total 四段测量 |
| 9.2 真实 IP 与转发头 | [课 9](../../stages/3-缓存与性能/lessons/lesson-09-代理网关与CDN.md) | 设计决策中的代理边界与“谁添加转发头”检查项 |
| 10.2 HTTP/1.1 关键特性 | [课 10](../../stages/4-协议演进/lessons/lesson-10-HTTP1.1与协议奠基.md) | 本地基线使用 HTTP/1.1、明确 `Host` 与响应长度 |
| 11.2 HTTP/2 多路复用 | [课 11](../../stages/4-协议演进/lessons/lesson-11-HTTP2与多路复用.md) | 协议决策要求测实际协商版本和瓶颈，不把升级当万能药 |
| 12.3 HTTP/3 部署决策 | [课 12](../../stages/4-协议演进/lessons/lesson-12-HTTP3与QUIC.md) | 记录 UDP/443、客户端、代理、回退条件 |
| 13.3 HTTP 认证头 | [课 13](../../stages/5-认证联调与决策/lessons/lesson-13-Cookie会话与Token.md) | `Authorization: Bearer` 与 `WWW-Authenticate` |
| 14.2 CORS 机制 | [课 14](../../stages/5-认证联调与决策/lessons/lesson-14-CORS与同源策略.md) | OPTIONS 预检、允许来源、允许方法/头部、`Vary: Origin` |
| 14.3 CORS 报错排查 | [课 14](../../stages/5-认证联调与决策/lessons/lesson-14-CORS与同源策略.md) | allowed/denied 两条预检分支与状态证据 |
| 15.1 抓包方法论 | [课 15](../../stages/5-认证联调与决策/lessons/lesson-15-抓包排障与决策清单.md) | DevTools、curl、标准库客户端三种观测镜头 |
| 15.2 综合排障推演 | [课 15](../../stages/5-认证联调与决策/lessons/lesson-15-抓包排障与决策清单.md) | 四个病例从症状到证据的可重复脚本 |
| 15.3 决策清单 | [课 15](../../stages/5-认证联调与决策/lessons/lesson-15-抓包排障与决策清单.md) | `验收清单.md` 与本 README 的证据卡字段 |

## 工程约束

本项目至少落实四项非功能约束：

| 约束 | 落实方式 |
|---|---|
| 安全 | 只监听 `127.0.0.1`；所有 token 都是占位符；客户端默认不打印认证正文；不安装抓包 CA、不解密第三方流量 |
| 性能可观测性 | 把连接、TTFB、正文读取、总耗时分开；服务端用 `Server-Timing` 暴露教学用阶段 |
| 错误语义 | 缺认证是 401，拒绝授权是 403，预检拒绝是 403，缓存命中是 304，不用 200 糊住错误 |
| 可维护性 | 服务、客户端、病例编排、回归测试分文件；路由行为集中在 `server.py`，病例断言集中在 `run_cases.py` |

## 项目边界

- 这是教学用 localhost 实验，不是生产认证服务、网关或 CDN。
- 未安装 mitmproxy，也不在项目中自动安装；代理和 HTTPS 解密只保留“隔离环境 + 用户明确授权 + 本地 CA 信任”的决策边界。
- 本地实现基线是 HTTP/1.1；HTTP/2、HTTP/3 的项目要求是收集真实协商和失败回退证据，不把本地结果冒充协议压测。
- `DEMO_TOKEN` 是字面量占位符。任何复制到真实项目的 token、Cookie、内网 URL 和用户数据都必须替换并脱敏。

## 文件说明

| 文件 | 用途 |
|---|---|
| `实现/server.py` | 本地诊断服务与四类故障路由 |
| `实现/client.py` | 可复用 HTTP 客户端与时间证据 |
| `实现/run_cases.py` | 四个病例的编排、断言与现场输出 |
| `实现/test_project.py` | 最小回归测试 |
| `实现/bad_server.py` | 能跑但语义、缓存、观测都糟糕的反例 |
| `证据卡示例.md` | 四个病例的可交接证据卡样例与空白模板 |
| `设计决策.md` | 四个真实权衡点 |
| `反例对照.md` | 正例与坏实现逐项对照 |
| `验收清单.md` | 学习者逐项验证的交付清单 |
| `assets/project-evidence-flow.svg` | 项目全链路图 |

## 完成标准

完成 [验收清单](验收清单.md) 后，应该能够把“页面慢 / 登录失效 / 跨域失败 / 重复下载”改写成团队可复核的证据卡，并说明下一步是修复、降级、升级协议，还是暂不改动。
