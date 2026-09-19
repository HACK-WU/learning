# 第 14 课评审记录：CORS 与同源策略

> 评审日期：2026-09-17
> 评审对象：课 14 正文、机制实验、应用实战及 4 张课级 SVG / 2 张应用实战 SVG
> 评审方式：主 agent 内联双视角（`course-reviewer` 子 agent 尚未创建，独立性受限）
> 评审依据：`topic-teach/review-dimensions.md` 全部 pedagogy / learner 维度；应用实战代码另做主 agent 静态正确性 review

## 结论

**P0=0，P1=0，P2=0，评审通过。** 已勾选 `network/http/00-评审清单.md` 的课 14 条目后交付。

本课没有把 curl 的 200 当成浏览器可读性证据，明确区分了服务端收到请求、浏览器完成 CORS 检查、脚本拿到响应三个层次；“simple request”同时标注为社区/历史称呼，并对齐当前 Fetch Standard 的 safelist 说法。

## 一、写前官方文档学习闸门与写后事实核查

| 事实点 | 核查来源 | 核查结论 | 课内落点 |
|---|---|---|---|
| origin 由协议、主机、端口组成 | [MDN Same-origin policy](https://developer.mozilla.org/en-US/docs/Web/Security/Defenses/Same-origin_policy) | 三元组一致才同源；路径不参与源比较 | 14.1 定义、SVG、URL 对照表 |
| CORS 是服务端声明跨源响应可共享的 HTTP 头机制 | [MDN CORS](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CORS)、[Fetch §3.3](https://fetch.spec.whatwg.org/#http-cors-protocol) | CORS 是浏览器读取许可，不是认证或通用防火墙 | 第一幕、14.2 核心原理 |
| 预检使用 OPTIONS，声明将来的方法与请求头 | [Fetch §3.3.2](https://fetch.spec.whatwg.org/#http-requests)、[MDN CORS preflight](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CORS#preflighted_requests) | `Access-Control-Request-Method/Headers` 与 `Allow-Methods/Headers` 分工一致 | 14.2 时序图、实验 |
| 预检不带凭证；凭证式响应不能用 Allow-Origin `*` | [Fetch §3.3.5](https://fetch.spec.whatwg.org/#http-cors-protocol-and-credentials)、[MDN credentialed requests](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CORS#requests_with_credentials) | 客户端 `credentials: include` 与服务端精确源/`Allow-Credentials: true` 需配套 | 14.2 凭证示例、误区 |
| simple request 是旧规范术语 | [MDN CORS](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CORS#simple_requests) | 当前 Fetch Standard 用 safelisted method/header 体系；课内并列保留实际工程常用词 | 14.2 首段、策略对照表 |
| CORS 失败如何定位 | [MDN CORS errors](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CORS/Errors) | 先看 DevTools，再按具体错误原因检查请求/响应；网络失败不必然是 CORS 配置 | 14.3 排查顺序、症状表 |
| 动态允许源与缓存 | [MDN Access-Control-Allow-Origin](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Access-Control-Allow-Origin) | 返回具体源时共享缓存场景应考虑 `Vary: Origin` | 14.2 与 14.3、应用实战 |

未涉及版本号、当期支持度、历史起源或行情数字；无需额外时点数据核查。没有调用源码探索：本课讲的是浏览器与 HTTP 标准，不是第三方库 API。

## 二、pedagogy 视角逐维度评审

| 维度 | 检查结果 | 证据 |
|---|---|---|
| 1. 教学逻辑 | 无问题 | 先判源（14.1）→ 再看许可与预检（14.2）→ 最后做证据对账（14.3），与阶段概览依赖一致；没有把 CORS 头放在同源概念之前。 |
| 2. 内容准确性 | 无问题 | `Origin` 三元组、预检头、凭证与 `*` 边界、`no-cors` opaque、错误响应与 Network 证据均与官方来源一致；实验输出真实运行。 |
| 3. 完整性 | 无问题 | 覆盖骨架承诺的 14.1 三元组/跨源读取、14.2 safelist/预检/Allow-* /凭证、14.3 三类报错/预检失败/服务端已配仍报错。 |
| 4. 格式规范 | 无问题 | 五幕齐全；课首零术语 SVG、本课地图、每个知识点的承接句/类比/边界/示例/误区/行话/官方文档齐全；14.1 与 14.3 的对比/分层/高分支内容用 SVG，14.2 的时序用 Mermaid；每张图均有读图指引；应用实战有双入口与逐步 SVG。 |
| 5. 一致性 | 无问题 | 与第 13 课的 Cookie/Authorization 术语衔接一致；与阶段 5 “先维持会话，再解决跨源凭证，最后抓包收束”的主线一致；没有把 CORS 与认证混为一谈。 |

## 三、learner 视角逐维度评审

代入角色：一名会写 `fetch()`、会用 curl，但还不会从浏览器 Network 还原 CORS 失败原因的入门全栈开发者。以下是学习者模拟阅读，不是真实用户测试。

| 维度 | 评审结果 | 学习者阅读证据 |
|---|---|---|
| L1 场景吸引力 | 无问题 | 第一幕先给 `localhost:5173` 调 `localhost:8000`、curl 200 与页面失败的真实联调冲突，没有用定义开场；场景本身只要求理解页面/API/浏览器，不比 CORS 更难。 |
| L2 由浅入深 | 无问题 | 第一幕先看到现象，第二幕形成“200 仍不可读”的冲突，第三幕从三格地址到许可头再到排查证据；新术语密度逐幕增加，没有一开始同时甩出全部 Allow-*。 |
| L3 认知阶梯平滑度 | 无问题 | 14.1 先用办公楼部门类比再引入 origin；14.2 先用访客申请单类比再进入预检；14.3 把错误文本还原为观察点；每个类比后都给失效边界。 |
| L4 故事弧完整性 | 无问题 | 小航的“curl 能通、页面读不到”贯穿五幕；14.1 解决地址边界，14.2 解决许可流程，14.3 解决定位；4.1 输出回扣第一幕，第五幕承接第 15 课抓包。 |
| L5 学习者困惑点 | 无问题 | 预先处理了最容易卡住的三组混淆：跨源不等于请求没发出、`simple request` 与 safelist 的术语关系、`*` 与凭证不能组合；每个新核心术语首次出现都有白话解释。 |
| L6 全局定位清晰度 | 无问题 | 第五幕明确课 13 的凭证承接、本课的浏览器读取边界和第 15 课的抓包收束；接力提示词精确指向课 15。 |
| L7 入口可读性 | 无问题 | “一句话本质”无 CORS/SOP 术语且给出不做/做的可观测对照；第三幕首 SVG 只画页面、服务、许可、读取闸门，不放本课术语；地图是三步表且未混入机制结论。 |
| L8 节奏与密度 | 无问题 | 表格、时序图、SVG、代码、症状表交替打断文字；非模板化亮点是“curl 200 vs 浏览器不可读”mini 案例和真实 MDN 错误类别；未出现同一幕连续四个纯文字段落。 |

## 四、应用实战代码正确性 review

| 检查项 | 结果 | 证据 |
|---|---|---|
| 每个演进步骤有代码 | 通过 | 14 实战包含基础公共 GET 与综合 `OPTIONS`/`POST` 及前端 fetch。 |
| 基础版逻辑 | 通过 | `Access-Control-Allow-Origin: *` 只用于不带凭证的公共读取，代码与文字边界一致。 |
| 综合版逻辑 | 通过 | 允许源、方法、请求头均按集合核对；`after_request` 给可信源的实际响应补头；预检成功返回 204，失败返回 403。 |
| 凭证边界 | 通过 | 前端使用 `credentials: "include"`；服务端返回具体源与 `Access-Control-Allow-Credentials: true`，没有 `*` + 凭证组合。 |
| 缓存边界 | 通过 | 具体源响应配 `Vary: Origin`；文本明确完整生产方案还需缓存/网关/CSRF 等设计。 |
| 敏感信息 | 通过 | 令牌为 `<ACCESS_TOKEN>` 占位符；域名为 `example.com` 文档专用域；无真实凭据、内网 URL 或个人信息。 |

结论：应用实战代码无需修改，未调用 `code-review` skill（按 topic-teach 规则由主 agent 直接静态 review）。

## 五、机械与运行验收

- 正文 535 行；应用实战 135 行，未超过课正文约三分之一的软锚点。
- 课级 SVG 4 张：全局入口、源三元组、排查阶梯、课程总结；应用实战分步 SVG 2 张；均为静态浅底 SVG，无 HTML/JS/SMIL 动画。
- `python3 -m py_compile network/http/stages/5-认证联调与决策/labs/lesson-14-cors-same-origin-lab.py`：通过。
- 本地实验 `--section all`：通过。源比较为 `same-origin / cross-origin / cross-origin`；允许预检 204；实际响应 200；拒绝预检 403 且无 Allow-Origin。
- 应用实战 Python 代码块 AST/compile 检查：2 个代码块通过。
- 新课正文、应用实战、索引、课程目录的本地链接检查：通过。
- 9 张新增 SVG 经 `xmllint --noout` 检查：通过。
- `network/http/` 教学产物敏感信息扫描：无命中。
- `git status --porcelain -- network/http/`：当前主题目录整体未跟踪，所有本轮 `.md` / `.svg` / `.py` 均属应保留教学产物；未执行 `git add` / `git commit`。

## 六、元数据处置

- `00-学习档案.md`：14.1–14.3 标记完成，追加本轮评审摘要。
- `00-评审清单.md`：课 14（含应用实战）从待评审改为已勾选。
- `02-课程目录.md`：课 14 与应用实战入口转为可点击链接。
- 阶段 5 `overview.md`：课 14 产出标记完成。
- `应用实战/INDEX.md`：新增并登记第 14 课实战。
- `AGENTS.md`：同步阶段 5 进度与课 14 交付物记录。
