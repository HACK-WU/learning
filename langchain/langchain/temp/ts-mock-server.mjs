// 本地 OpenAI 兼容 mock 端点（仅用于 TS 侧实测证据采集，不进入教程产物）
// 场景：双平台路径（/bailian/v1、/deepseek/v1，含延迟与对齐账单）、通用端点、SSE 流式、401/404/429
import http from "node:http";

const PORT = 8931;

function json(res, code, payload) {
  res.writeHead(code, { "Content-Type": "application/json" });
  res.end(JSON.stringify(payload));
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

// 每平台的用量序列（按请求序号），作为 TS 侧独立运行的模拟数值
const USAGE_SEQ = {
  bailian: [
    { prompt_tokens: 62, completion_tokens: 78, total_tokens: 140, reasoning_tokens: 42 },
    { prompt_tokens: 63, completion_tokens: 79, total_tokens: 142, reasoning_tokens: 43 },
    { prompt_tokens: 63, completion_tokens: 79, total_tokens: 142, reasoning_tokens: 43 },
  ],
  deepseek: [
    { prompt_tokens: 33, completion_tokens: 182, total_tokens: 215, reasoning_tokens: 152 },
    { prompt_tokens: 34, completion_tokens: 183, total_tokens: 217, reasoning_tokens: 153 },
    { prompt_tokens: 34, completion_tokens: 183, total_tokens: 217, reasoning_tokens: 153 },
  ],
};
const counters = { bailian: 0, deepseek: 0 };
let greetCounter = 0;
let respSeq = 0;
// 课 8：选择器场景标志——选择器 LLM 调用（json_schema）后紧跟主模型调用，用于路由消歧
let selectorScene = 0;

function completionBody(model, usage, extra) {
  return {
    id: `chatcmpl-mock-${++respSeq}`,
    object: "chat.completion",
    created: 1750000000,
    model,
    choices: [
      {
        index: 0,
        message: {
          role: "assistant",
          content: extra?.echo ?? "内存泄漏是指程序不再使用的内存没有被释放，导致可用内存逐渐被占用，最终可能变慢或崩溃。",
        },
        logprobs: null,
        finish_reason: "stop",
      },
    ],
    usage: {
      prompt_tokens: usage.prompt_tokens,
      completion_tokens: usage.completion_tokens,
      total_tokens: usage.total_tokens,
      completion_tokens_details: { reasoning_tokens: usage.reasoning_tokens },
    },
  };
}

const server = http.createServer(async (req, res) => {
  let body = "";
  req.on("data", (c) => (body += c));
  await new Promise((r) => req.on("end", r));

const url = req.url ?? "";

  // ============ 课 11：确定性 /embeddings 端点 ============
  // 字符级 n-gram hash 桶 → 稀疏向量 → L2 归一化。同一文本返回同一向量；
  // 字符重叠多的文本向量的余弦相似度更高（复现「语义相近→向量近」的教学意图）。
  // 支持 dimensions 参数做 MRL 截维（取前 dims 维）。仅供 TS 侧实测证据采集，不进入教程产物。
if (url.includes("/embeddings")) {
let ep = {};
    try {
      ep = JSON.parse(body);
    } catch {}
    const texts = Array.isArray(ep.input)
      ? ep.input.filter((t) => typeof t === "string")
      : typeof ep.input === "string"
        ? [ep.input]
        : [];
    const dims = typeof ep.dimensions === "number" ? Math.max(2, Math.floor(ep.dimensions)) : 4096;
    const norm = (v) => {
      let s = 0;
      for (const x of v) s += x * x;
      const r = Math.sqrt(s) || 1;
      return v.map((x) => x / r);
    };
const embedOne = (text) => {
      const full = Math.min(8192, Math.max(2, dims)); // 桶数=维度（MRL 截维：4096 与 1024 返回不同长度向量）
      const vec = new Array(full).fill(0);
      const grams = [];
      for (const ch of text) if (/[^\s]/.test(ch)) grams.push("1:" + ch);
      for (let i = 0; i < text.length - 1; i++) {
        const pair = text.slice(i, i + 2).replace(/\s+/g, " ");
        if (/[^\s\s]/.test(pair.replace(" ", "_"))) grams.push("2:" + pair);
      }
      for (let i = 0; i < text.length - 2; i++) {
        const tri = text.slice(i, i + 3).replace(/\s+/g, " ");
        grams.push("3:" + tri);
      }
      for (const g of grams) {
        let h = 2166136261;
        for (let i = 0; i < g.length; i++) {
          h ^= g.charCodeAt(i);
          h = Math.imul(h, 16777619) >>> 0;
        }
        vec[h % full] += 1;
      }
      return norm(vec);
    };
    const data = texts.map((t, i) => ({
      object: "embedding",
      index: i,
      embedding: embedOne(t),
    }));
    const tok = texts.reduce((a, t) => a + Math.ceil(t.length / 2), 0);
    const usage = { prompt_tokens: tok, total_tokens: tok };
    return json(res, 200, { object: "list", data, model: ep.model ?? "Qwen/Qwen3-Embedding-8B", usage });
  }

  if (!url.includes("/chat/completions")) {
    return json(res, 404, { error: { message: "path not found", type: "invalid_request_error" } });
  }
let payload = {};
  try {
    payload = JSON.parse(body);
  } catch {}
  const model = payload.model ?? "";
  const auth = String(req.headers["authorization"] ?? "");

  if (process.env.MOCK_DEBUG === "1") {
    const seq = (payload.messages ?? []).map((m) => {
      const tcs = m.tool_calls?.map((tc) => tc.function?.name).join(",");
      return `${m.role}${tcs ? `(${tcs})` : ""}:${String(m.content ?? "").slice(0, 30).replace(/\n/g, " ")}`;
    });
console.log(
      `[mock-req] model=${model} tools=[${(payload.tools ?? []).map((t) => t.function?.name).join(",")}] tool_choice=${JSON.stringify(payload.tool_choice ?? null)} enable_thinking=${JSON.stringify(payload.enable_thinking ?? null)} response_format=${JSON.stringify(payload.response_format ?? null)}`
    );
    console.log(`[mock-msgs] ${seq.join(" | ")}`);
  }

  if (auth.includes("invalid")) {
    return json(res, 401, {
      error: { message: "Invalid API key provided", type: "invalid_request_error", code: "invalid_api_key" },
    });
  }
if (model.includes("no-such") || model.includes("nonexistent")) {
    return json(res, 404, {
      error: { message: `The model \`${model}\` does not exist`, type: "invalid_request_error", code: "model_not_found" },
    });
  }
if (model.includes("rate-limited")) {
    return json(res, 429, {
      error: { message: "Rate limit reached for requests", type: "requests", code: "rate_limit_exceeded" },
    });
  }

// 课 5：模拟 thinking 模式拒绝强制工具选择（结构化输出场景；关掉思考模式的模型显式传 enable_thinking=false 可放行）
  if (payload.tool_choice === "required" && payload.enable_thinking !== false) {
    return json(res, 400, {
      error: {
        message: "The tool_choice parameter does not support being set to required or object in thinking mode",
        type: "invalid_request_error",
        code: "invalid_parameter_error",
      },
    });
  }

// 课 8：工具选择器的结构化输出请求（OpenAI 原生 json_schema 模式）
  if (payload.response_format?.type === "json_schema") {
    const allMsgs = payload.messages ?? [];
    const sysText8 = String(allMsgs.find((m) => m.role === "system")?.content ?? "");
    const userText8 = String([...allMsgs].reverse().find((m) => m.role === "user")?.content ?? "");
    if (sysText8.includes("select the most relevant tools")) {
      // 按用户问题选工具：天气 → get_weather；订单 → flaky_service
      let selected = ["get_weather"];
      if (/订单/.test(userText8)) selected = ["flaky_service"];
      if (/计算/.test(userText8)) selected = ["calculator"];
// 开启"选择器窗口"：紧随其后的主模型调用属于选择器场景（用于与课 3 的同话术路由消歧）
      selectorScene = 1;
      return json(res, 200, completionBody(model, { prompt_tokens: 180, completion_tokens: 14, total_tokens: 194, reasoning_tokens: 0 }, { echo: JSON.stringify({ tools: selected }) }));
    }
  }

if (payload.stream) {
    res.writeHead(200, {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      Connection: "keep-alive",
    });

    // ===== 课 6 流式场景路由 =====
    const sse = (obj) => res.write(`data: ${JSON.stringify(obj)}\n\n`);
    const sseFinish = (reason = "stop", usage = { prompt_tokens: 20, completion_tokens: 30, total_tokens: 50 }) => {
      sse({
        id: "chatcmpl-mock-stream",
        object: "chat.completion.chunk",
        created: 1750000000,
        model,
        choices: [{ index: 0, delta: {}, finish_reason: reason }],
        usage,
      });
      res.write("data: [DONE]\n\n");
      res.end();
    };
    const sseText = async (pieces, delayMs = 25) => {
      for (let i = 0; i < pieces.length; i++) {
        sse({
          id: "chatcmpl-mock-stream",
          object: "chat.completion.chunk",
          created: 1750000000,
          model,
          choices: [
            {
              index: 0,
              delta: i === 0 ? { role: "assistant", content: pieces[i] } : { content: pieces[i] },
              finish_reason: null,
            },
          ],
        });
        await sleep(delayMs);
      }
    };
    const sseEmptyDeltas = async (count, delayMs = 3) => {
      for (let i = 0; i < count; i++) {
        sse({
          id: "chatcmpl-mock-stream",
          object: "chat.completion.chunk",
          created: 1750000000,
          model,
          choices: [{ index: 0, delta: { content: "" }, finish_reason: null }],
        });
        await sleep(delayMs);
      }
    };
    const sseToolCalls = async (calls, delayMs = 25) => {
      sse({
        id: "chatcmpl-mock-stream",
        object: "chat.completion.chunk",
        created: 1750000000,
        model,
        choices: [{ index: 0, delta: { role: "assistant", content: "" }, finish_reason: null }],
      });
      await sleep(delayMs);
      for (let idx = 0; idx < calls.length; idx++) {
        const c = calls[idx];
        sse({
          id: "chatcmpl-mock-stream",
          object: "chat.completion.chunk",
          created: 1750000000,
          model,
          choices: [
            {
              index: 0,
              delta: { tool_calls: [{ index: idx, id: c.id, type: "function", function: { name: c.name, arguments: "" } }] },
              finish_reason: null,
            },
          ],
        });
        await sleep(delayMs);
        const args = JSON.stringify(c.args);
        const mid = Math.ceil(args.length / 2);
        for (const piece of [args.slice(0, mid), args.slice(mid)]) {
          sse({
            id: "chatcmpl-mock-stream",
            object: "chat.completion.chunk",
            created: 1750000000,
            model,
            choices: [{ index: 0, delta: { tool_calls: [{ index: idx, function: { arguments: piece } }] }, finish_reason: null }],
          });
          await sleep(delayMs);
        }
      }
      sseFinish("tool_calls", { prompt_tokens: 340, completion_tokens: 20, total_tokens: 360 });
    };

    const msgs6 = payload.messages ?? [];
    const lastUser6 = [...msgs6].reverse().find((m) => m.role === "user");
    const lastText6 =
      typeof lastUser6?.content === "string"
        ? lastUser6.content
        : Array.isArray(lastUser6?.content)
          ? lastUser6.content.filter((b) => b.type === "text").map((b) => b.text).join("")
          : "";
    const toolMsgs6 = msgs6.filter((m) => m.role === "tool" || m.role === "function");
    const toolNames6 = (payload.tools ?? []).map((t) => t.function?.name ?? t.name ?? "");
    const pickCity6 = () => (/北京/.test(lastText6) ? "北京" : /上海/.test(lastText6) ? "上海" : "广州");

    // 6-A/B/E：天气链（北京 / 上海 / 广州；get_weather）
    if (toolNames6.includes("get_weather") && /天气/.test(lastText6) && /北京|上海|广州/.test(lastText6)) {
      if (toolMsgs6.length === 0) {
        await sleep(1400);
        await sseToolCalls([{ id: `call_w6_${pickCity6()}`, name: "get_weather", args: { city: pickCity6() } }]);
      } else {
        await sleep(1400);
        const city = pickCity6();
        const answers = {
          北京: ["北京现在是晴天，", "气温22°C，", "湿度45%。"],
          上海: ["上海现在是晴天，", "气温22°C，", "湿度45%。"],
          广州: ["广州当前天气：晴天，", "气温 22°C，湿度 45%。", "天气不错，适合外出～"],
        };
        await sseText(answers[city]);
        sseFinish("stop", { prompt_tokens: 420, completion_tokens: 40, total_tokens: 460 });
      }
      return;
    }

    // 6-C：messages 逐块（"用一句话介绍北京"；分块形态对齐 Python 侧实测：5 内容块 + 34 空增量）
    if (lastText6.includes("用一句话介绍北京")) {
      await sleep(150);
      await sseText(["北京是中国", "的首都，也是一", "座融合了悠久历史", "与现代", "活力的国际化大都市。"], 30);
      await sseEmptyDeltas(34);
      sseFinish("stop", { prompt_tokens: 40, completion_tokens: 30, total_tokens: 70 });
      return;
    }

    // 6-D：custom 信号（搜索链；3 次并行 slow_search）
    if (toolNames6.includes("slow_search") && /搜索/.test(lastText6)) {
      if (toolMsgs6.length === 0) {
        await sleep(300);
        await sseToolCalls([
          { id: "call_s6_a1b2", name: "slow_search", args: { query: "LangChain streaming 最新文档" } },
          { id: "call_s6_c3d4", name: "slow_search", args: { query: "LangChain 三种流模式官方指南" } },
          { id: "call_s6_e5f6", name: "slow_search", args: { query: "LangGraph streaming 实践要点" } },
        ]);
      } else {
        await sleep(300);
        await sseText(["三次搜索共找到 9 条结果，", "核心结论：streaming 有三种流模式，", "v2 是当前默认、v3 是 beta 新协议。"]);
        sseFinish("stop", { prompt_tokens: 520, completion_tokens: 46, total_tokens: 566 });
      }
      return;
    }

// 10-2g: 流式配合（send_email → eve@corp.com；中断前文本流 + 恢复后继续）
    if (toolNames6.includes("send_email") && lastText6.includes("eve@corp.com")) {
      if (toolMsgs6.length === 0) {
        await sleep(200);
        await sseText(["好的，我先说明我的计划：", "准备给 eve@corp.com 发送一封主题为「流式测试」的邮件，", "这一步需要你审批。"]);
        await sseToolCalls([{ id: "call_l10_2g_01", name: "send_email", args: { recipient: "eve@corp.com", subject: "流式测试" } }]);
      } else {
        await sleep(200);
        await sseText(["邮件已发送给 eve@corp.com，主题：流式测试。"]);
        sseFinish("stop", { prompt_tokens: 340, completion_tokens: 18, total_tokens: 358 });
      }
      return;
    }

    // 旧：死锁流（课 1 遗留）
    const pieces = ["死锁是指两个", "或多个进程", "因互相等待", "对方持有的资源", "而永久阻塞。"];
    let i = 0;
    const send = () => {
      if (i < pieces.length) {
        const chunk = {
          id: "chatcmpl-mock-stream",
          object: "chat.completion.chunk",
          created: 1750000000,
          model,
          choices: [
            {
              index: 0,
              delta: i === 0 ? { role: "assistant", content: pieces[i] } : { content: pieces[i] },
              finish_reason: null,
            },
          ],
        };
        res.write(`data: ${JSON.stringify(chunk)}\n\n`);
        i++;
        setTimeout(send, 10);
      } else {
        const done = {
          id: "chatcmpl-mock-stream",
          object: "chat.completion.chunk",
          created: 1750000000,
          model,
          choices: [{ index: 0, delta: {}, finish_reason: "stop" }],
          usage: { prompt_tokens: 20, completion_tokens: 30, total_tokens: 50 },
        };
        res.write(`data: ${JSON.stringify(done)}\n\n`);
        res.write("data: [DONE]\n\n");
        res.end();
      }
    };
    send();
    return;
  }

  // 双平台路径：延迟 + 对齐账单
if (url.includes("/bailian/")) {
    await sleep(2900);
    const u = USAGE_SEQ.bailian[counters.bailian++ % USAGE_SEQ.bailian.length];
    return json(res, 200, completionBody(model, u));
  }
  if (url.includes("/deepseek/")) {
    await sleep(2200);
    const u = USAGE_SEQ.deepseek[counters.deepseek++ % USAGE_SEQ.deepseek.length];
    return json(res, 200, completionBody(model, u));
  }
  if (url.includes("/k4/")) {
    return json(res, 200, completionBody(model, { prompt_tokens: 68, completion_tokens: 43, total_tokens: 111, reasoning_tokens: 126 }));
  }

// 课 3 场景路由：根据消息内容返回不同文本
  const messages = payload.messages ?? [];
  const lastUser = [...messages].reverse().find((m) => m.role === "user");
  const lastContent = lastUser?.content;
  const lastText = typeof lastContent === "string" ? lastContent : Array.isArray(lastContent) ? lastContent.filter((b) => b.type === "text").map((b) => b.text).join("") : "";
const hasAssistantHistory = messages.some((m) => m.role === "assistant");
  const hasTools = Array.isArray(payload.tools) && payload.tools.length > 0;
  const lastIsTool = [...messages].reverse().find((m) => m.role === "tool" || m.role === "function");
  const hasWrongToolId = messages.some((m) => m.role === "tool" && String(m.tool_call_id ?? "").includes("WRONG"));
  const toolNames = (payload.tools ?? []).map((t) => t.function?.name ?? t.name ?? "");
  const hasToolNamed = (n) => toolNames.includes(n);
  const toolMsgs = messages.filter((m) => m.role === "tool" || m.role === "function");
  const lastToolContent = String(toolMsgs.length ? toolMsgs[toolMsgs.length - 1].content : "");

const toolCallBody = (calls, usage) => ({
    id: `chatcmpl-mock-${++respSeq}`,
    object: "chat.completion",
    created: 1750000000,
    model,
    choices: [
      {
        index: 0,
        message: {
          role: "assistant",
          content: "",
          tool_calls: calls.map((c) => ({
            id: c.id,
            type: "function",
            function: { name: c.name, arguments: JSON.stringify(c.args) },
          })),
        },
        finish_reason: "tool_calls",
      },
    ],
    usage: usage ?? { prompt_tokens: 320, completion_tokens: 24, total_tokens: 344 },
  });

// 工具调用链路（含错配/缺回执场景）
if (hasTools) {
const logResp = (kind) => {
      if (process.env.MOCK_DEBUG === "1") console.log(`[mock-resp] ${kind}`);
    };
// ==== 课 11 场景路由（带工具）：Agentic RAG（检索做工具）====
    if (hasToolNamed("search_knowledge_base")) {
      // 次轮：已有工具结果 → 基于检索内容返回最终回答
      if (lastIsTool) {
        const tb = lastToolContent;
        if (tb.includes("VPN")) {
          return json(res, 200, completionBody(model, { prompt_tokens: 640, completion_tokens: 130, total_tokens: 770, reasoning_tokens: 0 }, { echo: "**VPN 客户端名称：NebulaConnect**（支持 Windows、macOS 与移动端）。重置密码可访问 `it.nebula-tech.example` 自助操作；账号为员工工号，初始密码入职时由 IT 服务台发放。" }));
        }
        if (tb.includes("每年")) {
          return json(res, 200, completionBody(model, { prompt_tokens: 660, completion_tokens: 120, total_tokens: 780, reasoning_tokens: 0 }, { echo: "星云科技年假按在公司的连续服务年限阶梯计算：\n- 入职满 1 年不满 3 年：每年 5 天\n- 入职满 3 年不满 5 年：每年 10 天\n- 入职满 5 年及以上：每年 15 天\n全年累计事假超过 15 天的，次年年假按比例折算。" }));
        }
        return json(res, 200, completionBody(model, { prompt_tokens: 700, completion_tokens: 140, total_tokens: 840, reasoning_tokens: 0 }, { echo: "您好！针对您的问题：\n- **年假申请**需提前 **5 个工作日**提交（来源：01-考勤与休假制度.md）。\n- **北京出差住宿**每晚上限 **600 元**、市内交通每日上限 **150 元**（来源：02-报销与费用标准.md）。\n如需预订或报销，可随时告诉我。" }));
      }
      // 首轮：根据问题返回工具调用（可能并行多条）
      logResp("K11:call:search_knowledge_base");
      if (lastText.includes("每年有多少天年假")) {
        return json(res, 200, toolCallBody([{ id: "call_l11_year_01", name: "search_knowledge_base", args: { query: "员工年假天数 政策" } }], { prompt_tokens: 520, completion_tokens: 24, total_tokens: 544 }));
      }
      if (lastText.includes("VPN 客户端叫什么") && lastText.includes("怎么重置密码")) {
        return json(res, 200, toolCallBody([
          { id: "call_l11_vpn_01", name: "search_knowledge_base", args: { query: "VPN 客户端名称" } },
          { id: "call_l11_vpn_02", name: "search_knowledge_base", args: { query: "VPN 密码重置 忘记" } },
        ], { prompt_tokens: 540, completion_tokens: 40, total_tokens: 580 }));
      }
      if (lastText.includes("北京出差")) {
        return json(res, 200, toolCallBody([
          { id: "call_l11_travel_01", name: "search_knowledge_base", args: { query: "年假申请 提前 工作日" } },
          { id: "call_l11_travel_02", name: "search_knowledge_base", args: { query: "北京 出差 住宿 报销" } },
        ], { prompt_tokens: 600, completion_tokens: 40, total_tokens: 640 }));
      }
      // 兜底：单条
      return json(res, 200, toolCallBody([{ id: "call_l11_kb_01", name: "search_knowledge_base", args: { query: lastText.slice(0, 20) } }], { prompt_tokens: 500, completion_tokens: 24, total_tokens: 524 }));
    }
// ==== 课 10 场景路由（带工具）：HITL 人机协同 & 护栏 ====
    // 10-1b: read_inbox 未设闸门 → 直通执行（首轮调工具 / 执行后回文本）
    if (hasToolNamed("read_inbox") && lastText.includes("收件箱有几封新邮件")) {
      if (lastIsTool) return json(res, 200, completionBody(model, { prompt_tokens: 300, completion_tokens: 16, total_tokens: 316, reasoning_tokens: 0 }, { echo: "收件箱里有 3 封新邮件。" }));
      logResp("K10-1b:call:read_inbox");
      return json(res, 200, toolCallBody([{ id: "call_l10_rb_01", name: "read_inbox", args: {} }]));
    }
    // 10-1a: send_email 审批（alice / 周会提醒）
    if (hasToolNamed("send_email") && lastText.includes("周会提醒")) {
      if (lastIsTool) return json(res, 200, completionBody(model, { prompt_tokens: 340, completion_tokens: 22, total_tokens: 362, reasoning_tokens: 0 }, { echo: "邮件已成功发送给 alice@corp.com，主题：周会提醒。" }));
      logResp("K10-1a:call:send_email");
      return json(res, 200, toolCallBody([{ id: "call_l10_1a_01", name: "send_email", args: { recipient: "alice@corp.com", subject: "周会提醒" } }]));
    }
    // 10-2a: reject（spam-list 广告 → 拒绝后模型改道）
    if (hasToolNamed("send_email") && lastText.includes("spam-list@corp.com")) {
      if (toolMsgs.length > 0) return json(res, 200, completionBody(model, { prompt_tokens: 350, completion_tokens: 36, total_tokens: 386, reasoning_tokens: 0 }, { echo: "抱歉，我无法向外部列表群发广告邮件——公司政策不允许这种操作。" }));
      logResp("K10-2a:call:send_email");
      return json(res, 200, toolCallBody([{ id: "call_l10_2a_01", name: "send_email", args: { recipient: "spam-list@corp.com", subject: "广告" } }]));
    }
    // 10-2b: edit（charlie 草稿 → 改后 dave）
    if (hasToolNamed("send_email") && lastText.includes("charlie@corp.com")) {
      if (toolMsgs.length > 0) return json(res, 200, completionBody(model, { prompt_tokens: 360, completion_tokens: 30, total_tokens: 390, reasoning_tokens: 0 }, { echo: "已按修改后的收件人 dave@corp.com 发送邮件，主题：修改后的主题。" }));
      logResp("K10-2b:call:send_email");
      return json(res, 200, toolCallBody([{ id: "call_l10_2b_01", name: "send_email", args: { recipient: "charlie@corp.com", subject: "草稿" } }]));
    }
    // 10-2c: ask_user（respond 人工代答；工具真实实现不执行）
    if (hasToolNamed("ask_user") && lastText.includes("订一张机票")) {
      logResp("K10-2c:call:ask_user");
      return json(res, 200, toolCallBody([{ id: "call_l10_2c_01", name: "ask_user", args: { question: "请问您想订哪天的机票、从哪到哪、舱位等级呢？" } }]));
    }
// 10-2d: 批量决策（并行两封邮件：alice 批准 / bob 拒绝；与讲义 C 段叙述一致）
    if (hasToolNamed("send_email") && lastText.includes("alice@corp.com") && lastText.includes("bob@corp.com")) {
      if (toolMsgs.length > 0) return json(res, 200, completionBody(model, { prompt_tokens: 420, completion_tokens: 40, total_tokens: 460, reasoning_tokens: 0 }, { echo: "已按审批结果处理批量请求：给 alice 的邮件已批准并发送；给 bob 的邮件被拒绝（审批人未同意）。" }));
      logResp("K10-2d:call:batch");
      return json(res, 200, toolCallBody([
        { id: "call_l10_2d_alice", name: "send_email", args: { recipient: "alice@corp.com", subject: "批量邮件" } },
        { id: "call_l10_2d_bob", name: "send_email", args: { recipient: "bob@corp.com", subject: "批量邮件" } },
      ]));
    }
    // 10-2e: 条件中断（internal.com 直通 → 首轮调工具 / 执行后回文本）
    if (hasToolNamed("send_email") && lastText.includes("内部同步")) {
      if (lastIsTool) return json(res, 200, completionBody(model, { prompt_tokens: 320, completion_tokens: 18, total_tokens: 338, reasoning_tokens: 0 }, { echo: "已直接发送内部邮件给 teammate@internal.com（内部域名直通，无需审批）。" }));
      logResp("K10-2e:call:send_email");
      return json(res, 200, toolCallBody([{ id: "call_l10_2e_01", name: "send_email", args: { recipient: "teammate@internal.com", subject: "内部同步" } }]));
    }
    // 10-2f: v2 形态（v2test@corp.com；TS 默认 v2）
    if (hasToolNamed("send_email") && lastText.includes("v2test@corp.com")) {
      if (lastIsTool) return json(res, 200, completionBody(model, { prompt_tokens: 340, completion_tokens: 18, total_tokens: 358, reasoning_tokens: 0 }, { echo: "邮件已发送给 v2test@corp.com，主题：v2 形态。" }));
      logResp("K10-2f:call:send_email");
      return json(res, 200, toolCallBody([{ id: "call_l10_2f_01", name: "send_email", args: { recipient: "v2test@corp.com", subject: "v2 形态" } }]));
    }
    // 10-2g: 流式配合（eve@corp.com）
    if (hasToolNamed("send_email") && lastText.includes("eve@corp.com")) {
      if (lastIsTool) return json(res, 200, completionBody(model, { prompt_tokens: 340, completion_tokens: 18, total_tokens: 358, reasoning_tokens: 0 }, { echo: "邮件已发送给 eve@corp.com，主题：流式测试。" }));
      logResp("K10-2g:call:send_email");
      return json(res, 200, toolCallBody([{ id: "call_l10_2g_01", name: "send_email", args: { recipient: "eve@corp.com", subject: "流式测试" } }]));
    }
    // 10-2h: 决策数量不匹配（count@corp.com；多给一个决策 → 报错）
    if (hasToolNamed("send_email") && lastText.includes("count@corp.com")) {
      if (lastIsTool) return json(res, 200, completionBody(model, { prompt_tokens: 340, completion_tokens: 16, total_tokens: 356, reasoning_tokens: 0 }, { echo: "邮件已发送给 count@corp.com，主题：数量核对。" }));
      logResp("K10-2h:call:send_email");
      return json(res, 200, toolCallBody([{ id: "call_l10_2h_01", name: "send_email", args: { recipient: "count@corp.com", subject: "数量核对" } }]));
    }
    // ==== 课 9 场景路由（带工具）====
    // 9-1a: 组装视图（get_weather 单轮）
    if (hasToolNamed("get_weather") && lastText.includes("北京天气怎么样？")) {
      if (lastIsTool) {
        logResp("K9-1a:final");
        return json(res, 200, completionBody(model, { prompt_tokens: 380, completion_tokens: 14, total_tokens: 394, reasoning_tokens: 0 }, { echo: "北京 晴天，22°C" }));
      }
      logResp("K9-1a:call:get_weather");
      return json(res, 200, toolCallBody([{ id: "call_k9_w1", name: "get_weather", args: { city: "北京" } }]));
    }
    // 9-2e: 角色过滤（viewer 只见 read_data → 删除被拒；admin 见三工具 → 能读取）
    if (hasToolNamed("read_data") && !hasToolNamed("delete_data") && lastText.includes("请删除所有业务数据")) {
      logResp("K9-2e:final(viewer)");
      return json(res, 200, completionBody(model, { prompt_tokens: 380, completion_tokens: 46, total_tokens: 426, reasoning_tokens: 0 }, { echo: "很抱歉，我无法执行这个请求。我仅有的工具是 read_data（读取业务数据），我并不具备任何删除数据的能力。" }));
    }
    if (hasToolNamed("delete_data") && lastText.includes("请读取业务数据")) {
      if (lastIsTool) {
        logResp("K9-2e:final(admin)");
        return json(res, 200, completionBody(model, { prompt_tokens: 400, completion_tokens: 12, total_tokens: 412, reasoning_tokens: 0 }, { echo: "业务数据读取结果：**42**。" }));
      }
      logResp("K9-2e:call:read_data");
      return json(res, 200, toolCallBody([{ id: "call_k9_rd_01", name: "read_data", args: {} }]));
    }
    // 9-2g: 长报告（工具在 TS 侧真正生成 1144 字；模型看短版）
    if (hasToolNamed("big_report") && lastText.includes("请获取主题报告")) {
      if (lastIsTool) {
        logResp("K9-2g:final");
        return json(res, 200, completionBody(model, { prompt_tokens: 400, completion_tokens: 6, total_tokens: 406, reasoning_tokens: 0 }, { echo: "**已阅**" }));
      }
      logResp("K9-2g:call:big_report");
      return json(res, 200, toolCallBody([{ id: "call_k9_br_01", name: "big_report", args: { topic: "主题" } }]));
    }
    // 9-3a: 工具读 runtime.context（user_id）
    if (hasToolNamed("get_my_user_id") && lastText.includes("请查询我的用户 ID")) {
      if (lastIsTool) {
        logResp("K9-3a:final");
        return json(res, 200, completionBody(model, { prompt_tokens: 390, completion_tokens: 18, total_tokens: 408, reasoning_tokens: 0 }, { echo: "您的用户 ID 是：**user_777**。" }));
      }
      logResp("K9-3a:call:get_my_user_id");
      return json(res, 200, toolCallBody([{ id: "call_k9_uid_01", name: "get_my_user_id", args: {} }]));
    }
    // 9-3b: login（Command 写状态）→ check_auth（读状态）
    if (hasToolNamed("login") && lastText.includes("请先用密码 correct 登录")) {
      if (lastToolContent.includes("当前登录状态")) {
        logResp("K9-3b:final");
        return json(res, 200, completionBody(model, { prompt_tokens: 430, completion_tokens: 22, total_tokens: 452, reasoning_tokens: 0 }, { echo: "登录成功，当前登录状态已认证（authenticated = true）。" }));
      }
      if (lastToolContent.includes("登录成功")) {
        logResp("K9-3b:call:check_auth");
        return json(res, 200, toolCallBody([{ id: "call_k9_auth_01", name: "check_auth", args: {} }]));
      }
      logResp("K9-3b:call:login");
      return json(res, 200, toolCallBody([{ id: "call_k9_login_01", name: "login", args: { password: "correct" } }]));
    }
    // 9-3c: store 跨会话（会话 A 保存 / 会话 B 读取）
    if (hasToolNamed("save_preference") && lastText.includes("请保存我的偏好")) {
      if (lastIsTool) {
        logResp("K9-3c:final(save)");
        return json(res, 200, completionBody(model, { prompt_tokens: 410, completion_tokens: 26, total_tokens: 436, reasoning_tokens: 0 }, { echo: "已保存你的偏好：语言 = **中文**。" }));
      }
      logResp("K9-3c:call:save_preference");
      return json(res, 200, toolCallBody([{ id: "call_k9_pref_save", name: "save_preference", args: { key: "语言", value: "中文" } }]));
    }
    if (hasToolNamed("get_preference") && lastText.includes("请读取我的偏好")) {
      if (lastIsTool) {
        logResp("K9-3c:final(get)");
        return json(res, 200, completionBody(model, { prompt_tokens: 410, completion_tokens: 30, total_tokens: 440, reasoning_tokens: 0 }, { echo: "已读取你的偏好「语言」：**中文**。之后我都会用中文与你交流。" }));
      }
      logResp("K9-3c:call:get_preference");
      return json(res, 200, toolCallBody([{ id: "call_k9_pref_get", name: "get_preference", args: { key: "语言" } }]));
    }
    // 9-4b: 审计钩子（get_weather 工具链）
    if (hasToolNamed("get_weather") && lastText.includes("查一下北京天气")) {
      if (lastIsTool) {
        logResp("K9-4b:final");
        return json(res, 200, completionBody(model, { prompt_tokens: 420, completion_tokens: 40, total_tokens: 460, reasoning_tokens: 0 }, { echo: "北京天气：晴天，22°C。" }));
      }
      logResp("K9-4b:call:get_weather");
      return json(res, 200, toolCallBody([{ id: "call_k9_audit_w1", name: "get_weather", args: { city: "北京" } }]));
    }
    // ---- 课 7 场景路由（带工具）----
    // 7-2d: 自定义 state：save_name → Command 写状态 / get_name 读状态
    if (hasToolNamed("save_name") && lastText.includes("我的名字是小明，请记录下来")) {
      if (lastToolContent.includes("已记录")) {
        logResp("K7-2d:final(save_name)");
        return json(res, 200, completionBody(model, { prompt_tokens: 430, completion_tokens: 26, total_tokens: 456, reasoning_tokens: 0 }, { echo: "好的，我已经记录下您的名字：**小明**。" }));
      }
      logResp("K7-2d:call:save_name");
      return json(res, 200, toolCallBody([{ id: "call_k7_save_name_01", name: "save_name", args: { name: "小明" } }]));
    }
    if (hasToolNamed("get_name") && lastText.includes("我之前说我的名字是什么")) {
      if (lastToolContent.includes("之前记录的用户名")) {
        logResp("K7-2d:final(get_name)");
        return json(res, 200, completionBody(model, { prompt_tokens: 446, completion_tokens: 20, total_tokens: 466, reasoning_tokens: 0 }, { echo: "您之前告诉我的名字是：**小明**。" }));
      }
      logResp("K7-2d:call:get_name");
      return json(res, 200, toolCallBody([{ id: "call_k7_get_name_01", name: "get_name", args: {} }]));
    }
    // 7-3b: 跨线程召回：session-1 教名字 / session-2 查名字（user_123）
    if (hasToolNamed("save_user_name") && lastText.includes("记住：我叫小明")) {
      if (lastToolContent.includes("已保存")) {
        logResp("K7-3b:final(save_user_name)");
        return json(res, 200, completionBody(model, { prompt_tokens: 430, completion_tokens: 30, total_tokens: 460, reasoning_tokens: 0 }, { echo: "好的，小明，我已经记住你的名字啦！😊 有什么我可以帮你的吗？" }));
      }
      logResp("K7-3b:call:save_user_name");
      return json(res, 200, toolCallBody([{ id: "call_k7_save_user_01", name: "save_user_name", args: { name: "小明" } }]));
    }
    // 7-3b/3c: 查名字（3b 有记录 / 3c 换 user_456 无记录）
    if (hasToolNamed("get_user_name") && lastText.includes("我叫什么名字")) {
      if (lastToolContent.includes("没有找到")) {
        logResp("K7-3c:final(no-record)");
        return json(res, 200, completionBody(model, { prompt_tokens: 440, completion_tokens: 48, total_tokens: 488, reasoning_tokens: 0 }, { echo: "我这边还没有关于你姓名的记录，所以暂时不知道你的名字 😊 如果你愿意告诉我，我可以帮你记下来，以后就能随时叫出你的名字啦。" }));
      }
      if (lastToolContent.includes("小明")) {
        logResp("K7-3b:final(get_user_name)");
        return json(res, 200, completionBody(model, { prompt_tokens: 442, completion_tokens: 10, total_tokens: 452, reasoning_tokens: 0 }, { echo: "你叫小明 😊" }));
      }
      logResp("K7-3b/3c:call:get_user_name");
      return json(res, 200, toolCallBody([{ id: "call_k7_get_user_01", name: "get_user_name", args: {} }]));
    }
// 7-3d: 更新记忆（改名 → put 覆盖同 key）
    if (hasToolNamed("save_user_name") && lastText.includes("改个名字")) {
      if (lastToolContent.includes("大明")) {
        logResp("K7-3d:final(save_user_name)");
        return json(res, 200, completionBody(model, { prompt_tokens: 452, completion_tokens: 34, total_tokens: 486, reasoning_tokens: 0 }, { echo: "好的，大明，已经帮你更新啦 ✅ 以后我就这样称呼你。有什么需要尽管说！" }));
      }
      logResp("K7-3d:call:save_user_name");
      return json(res, 200, toolCallBody([{ id: "call_k7_save_user_02", name: "save_user_name", args: { name: "大明" } }]));
    }
// 7-4a: profile 合并更新（读 → 改 → 写）
    if (hasToolNamed("remember_preference") && lastText.includes("我喜欢喝咖啡")) {
      if (lastToolContent.includes("已记住")) {
        logResp("K7-4a:final(remember_preference)");
        return json(res, 200, completionBody(model, { prompt_tokens: 470, completion_tokens: 36, total_tokens: 506, reasoning_tokens: 0 }, { echo: "好的，已记住你喜欢喝咖啡。以后在推荐或安排相关事项时，我会把这一点考虑进去。" }));
      }
      logResp("K7-4a:call:remember_preference");
      return json(res, 200, toolCallBody([{ id: "call_k7_pref_01", name: "remember_preference", args: { preference: "我喜欢喝咖啡。" } }]));
    }
    // ---- 课 8 场景路由（带工具）----
    // 8-1a: 钩子全景（calculator 单轮；6*7）
    if (hasToolNamed("calculator") && lastText.includes("请用计算器算 6*7")) {
      if (lastIsTool) {
        logResp("K8-1a:final");
        return json(res, 200, completionBody(model, { prompt_tokens: 390, completion_tokens: 12, total_tokens: 402, reasoning_tokens: 0 }, { echo: "6 × 7 = **42**" }));
      }
      logResp("K8-1a:call:calculator");
      return json(res, 200, toolCallBody([{ id: "call_k8_calc_6x7", name: "calculator", args: { expression: "6*7" } }]));
    }
    // 8-3a: 计数中间件（8*9）
    if (hasToolNamed("calculator") && lastText.includes("请用计算器算 8*9")) {
      if (lastIsTool) {
        logResp("K8-3a:final");
        return json(res, 200, completionBody(model, { prompt_tokens: 400, completion_tokens: 12, total_tokens: 412, reasoning_tokens: 0 }, { echo: "8 × 9 = **72**" }));
      }
      logResp("K8-3a:call:calculator");
      return json(res, 200, toolCallBody([{ id: "call_k8_calc_8x9", name: "calculator", args: { expression: "8*9" } }]));
    }
    // 8-4a: 三中间件顺序（1234*5678）
    if (hasToolNamed("calculator") && lastText.includes("请用计算器算 1234*5678")) {
      if (lastIsTool) {
        logResp("K8-4a:final");
        return json(res, 200, completionBody(model, { prompt_tokens: 402, completion_tokens: 16, total_tokens: 418, reasoning_tokens: 0 }, { echo: "1234 × 5678 = **7006652**" }));
      }
      logResp("K8-4a:call:calculator");
      return json(res, 200, toolCallBody([{ id: "call_k8_calc_big", name: "calculator", args: { expression: "1234*5678" } }]));
    }
    // 8-2a: 模型限额（runLimit=2 拦下第 3 次汇总调用）
    if (hasToolNamed("get_weather") && lastText.includes("先查北京天气")) {
      if (toolMsgs.length === 0) {
        logResp("K8-2a:call:get_weather");
        return json(res, 200, toolCallBody([{ id: "call_k8_mcl_w1", name: "get_weather", args: { city: "北京" } }]));
      }
      if (toolMsgs.length === 1) {
        logResp("K8-2a:call:get_time");
        return json(res, 200, toolCallBody([{ id: "call_k8_mcl_t1", name: "get_time", args: { city: "北京" } }]));
      }
      logResp("K8-2a:final(溢出路径-不应发生)");
      return json(res, 200, completionBody(model, { prompt_tokens: 440, completion_tokens: 42, total_tokens: 482, reasoning_tokens: 0 }, { echo: "出行建议：北京晴天 22°C、当前 14:30，适宜出行。" }));
    }
    // 8-2b: 工具限额（calculator 限 1 次，并行两调用拦下一个）
    if (hasToolNamed("calculator") && lastText.includes("请连续用计算器算两次")) {
      if (lastIsTool) {
        logResp("K8-2b:final");
        return json(res, 200, completionBody(model, { prompt_tokens: 460, completion_tokens: 66, total_tokens: 526, reasoning_tokens: 0 }, { echo: "第一次计算器结果：**12 × 8 = 96**。第二次调用时工具返回了「超过调用次数限制」，所以没能用计算器算。手算结果是：**15 × 7 = 105**。" }));
      }
      logResp("K8-2b:call:calculator x2");
      return json(res, 200, toolCallBody([
        { id: "call_k8_tcl_a1", name: "calculator", args: { expression: "12*8" } },
        { id: "call_k8_tcl_b2", name: "calculator", args: { expression: "15*7" } },
      ]));
    }
    // 8-2c: 工具重试（flaky_service 前两败后成功）
    if (hasToolNamed("flaky_service") && lastText.includes("请查询订单 A100")) {
      if (lastIsTool) {
        logResp("K8-2c:final");
        return json(res, 200, completionBody(model, { prompt_tokens: 420, completion_tokens: 26, total_tokens: 446, reasoning_tokens: 0 }, { echo: "查询完成 ✅ 订单 **A100** 的结果为：**42**" }));
      }
      logResp("K8-2c:call:flaky_service");
      return json(res, 200, toolCallBody([{ id: "call_k8_retry_01", name: "flaky_service", args: { query: "订单 A100" } }]));
    }
    // 8-2d: 工具错误（strict_divide 除零；按回执区分 TS 默认兜底 vs ToolErrorMiddleware）
    if (hasToolNamed("strict_divide") && lastText.includes("请算 10 除以 0")) {
      if (lastIsTool) {
        if (lastToolContent.includes("请调整输入后重试")) {
          logResp("K8-2d:final(toolErrorMiddleware)");
          return json(res, 200, completionBody(model, { prompt_tokens: 430, completion_tokens: 58, total_tokens: 488, reasoning_tokens: 0 }, { echo: "算不了 —— 10 除以 0 在数学上是**未定义**的。 刚才调用 `strict_divide(10, 0)` 时，工具按设计直接抛出了 `ValueError`，而不是返回一个数字。" }));
        }
        logResp("K8-2d:final(ts-default)");
        return json(res, 200, completionBody(model, { prompt_tokens: 428, completion_tokens: 52, total_tokens: 480, reasoning_tokens: 0 }, { echo: "算不了 —— 10 除以 0 在数学上是**未定义**的。工具返回了错误提示（除数不能为 0），需要换一个除数再试。" }));
      }
      logResp("K8-2d:call:strict_divide");
      return json(res, 200, toolCallBody([{ id: "call_k8_div_01", name: "strict_divide", args: { a: 10, b: 0 } }]));
    }
// 8-2g/4b: 工具选择器与观察者（selectorScene 窗口内命中；与课 3 同话术消歧）
    if (selectorScene && lastText.includes("北京今天天气怎么样")) {
      selectorScene = 0;
      if (lastIsTool) {
        logResp("K8-2g/4b:final");
        return json(res, 200, completionBody(model, { prompt_tokens: 400, completion_tokens: 18, total_tokens: 418, reasoning_tokens: 0 }, { echo: "北京今天天气：晴，气温 26℃。适合出行。" }));
      }
      logResp("K8-2g/4b:call:get_weather");
      return json(res, 200, toolCallBody([{ id: "call_k8_sel_w1", name: "get_weather", args: { city: "北京" } }]));
    }
// 8-2h: 待办清单（两段观察：自主跳过 vs 明确要求闭环）
    // 场景一：多步任务但未要求用清单 → 模型直接干活（跳过 write_todos）
    if (hasToolNamed("write_todos") && lastText.includes("这是一个多步任务") && !lastText.includes("待办清单")) {
      if (toolMsgs.length >= 2) {
        logResp("K8-2h:skip:final");
        return json(res, 200, completionBody(model, { prompt_tokens: 470, completion_tokens: 40, total_tokens: 510, reasoning_tokens: 0 }, { echo: "已完成：北京天气晴天 22°C，当前时间 14:30。出行建议：天气不错，适宜外出。" }));
      }
      logResp("K8-2h:skip:call:get_weather+get_time");
      return json(res, 200, toolCallBody([
        { id: "call_k8_skip_w1", name: "get_weather", args: { city: "北京" } },
        { id: "call_k8_skip_t1", name: "get_time", args: { city: "北京" } },
      ]));
    }
    // 场景二：明确要求"先用待办清单列出计划" → 完整闭环
    if (hasToolNamed("write_todos") && lastText.includes("先用待办清单列出计划")) {
      if (toolMsgs.length === 0) {
        logResp("K8-2h:call:write_todos(init)");
        return json(res, 200, toolCallBody([{ id: "call_k8_todo_01", name: "write_todos", args: { todos: [
          { content: "第一步：查询北京天气", status: "in_progress" },
          { content: "第二步：查询北京当前时间", status: "in_progress" },
          { content: "第三步：汇总天气和时间，给出一句出行建议", status: "pending" },
        ] } }]));
      }
      if (lastToolContent.includes("Updated todo list")) {
        if (lastToolContent.includes("completed")) {
          logResp("K8-2h:final");
          return json(res, 200, completionBody(model, { prompt_tokens: 520, completion_tokens: 48, total_tokens: 568, reasoning_tokens: 0 }, { echo: "任务已全部完成，汇报如下： **查询结果** - 北京天气：晴天，22°C - 北京当前时间：14:30" }));
        }
        logResp("K8-2h:call:get_weather+get_time");
        return json(res, 200, toolCallBody([
          { id: "call_k8_todo_w1", name: "get_weather", args: { city: "北京" } },
          { id: "call_k8_todo_t1", name: "get_time", args: { city: "北京" } },
        ]));
      }
      logResp("K8-2h:call:write_todos(done)");
      return json(res, 200, toolCallBody([{ id: "call_k8_todo_02", name: "write_todos", args: { todos: [
        { content: "第一步：查询北京天气", status: "completed" },
        { content: "第二步：查询北京当前时间", status: "completed" },
        { content: "第三步：汇总天气和时间，给出一句出行建议", status: "completed" },
      ] } }]));
    }
// ---- 课 6 场景路由（非流式 invoke 对照）----
    if (hasToolNamed("get_weather") && /天气/.test(lastText) && /北京|上海|广州/.test(lastText) && !lastText.includes("北京和上海") && !lastText.includes("北京今天天气怎么样")) {
      await sleep(1400);
      if (lastIsTool) {
        logResp("K6-invoke:final");
        return json(res, 200, completionBody(model, { prompt_tokens: 420, completion_tokens: 40, total_tokens: 460, reasoning_tokens: 0 }, { echo: "北京现在是晴天，气温22°C，湿度45%。" }));
      }
      logResp("K6-invoke:call:get_weather");
      return json(res, 200, toolCallBody([{ id: "call_w6_invoke_01", name: "get_weather", args: { city: "北京" } }]));
    }
    // ---- 课 6 场景路由（custom 信号：slow_search 链，非流式模型调用）----
    if (hasToolNamed("slow_search") && /搜索/.test(lastText)) {
      if (toolMsgs.length === 0) {
        logResp("K6-custom:call:slow_search x3");
        return json(res, 200, toolCallBody([
          { id: "call_s6_a1b2", name: "slow_search", args: { query: "LangChain streaming 最新文档" } },
          { id: "call_s6_c3d4", name: "slow_search", args: { query: "LangChain 三种流模式官方指南" } },
          { id: "call_s6_e5f6", name: "slow_search", args: { query: "LangGraph streaming 实践要点" } },
        ]));
      }
      logResp("K6-custom:final");
      return json(res, 200, completionBody(model, { prompt_tokens: 520, completion_tokens: 46, total_tokens: 566, reasoning_tokens: 0 }, { echo: "三次搜索共找到 9 条结果。核心结论：streaming 有三种流模式，v2 是当前默认、v3 是 beta 新协议。" }));
    }
    // ---- 课 5 场景路由 ----
    // 5-1. 结构化输出：thinking 关闭后，返回"虚拟工具"调用（含自我校准 / 多输出重试两个剧本）
if (payload.tool_choice === "required") {
      // 课 9 2f：格式收窄（Simple → Detailed，toolStrategy 候选收窄）
      if (hasToolNamed("Simple")) {
        logResp("K9-2f:Simple");
        return json(res, 200, toolCallBody([{ id: "call_k9_2f_s1", name: "Simple", args: { answer: "你好！👋 有什么我可以帮你的吗？" } }]));
      }
      if (hasToolNamed("Detailed")) {
        logResp("K9-2f:Detailed");
        return json(res, 200, toolCallBody([{ id: "call_k9_2f_d1", name: "Detailed", args: { answer: "你好，我是一个能给出带置信度回答的通用助手。", confidence: 1.0 } }]));
      }
      if (hasToolNamed("EventDetails")) {
        // Union 场景：第一轮一口气调两个；错误回执后第二次只调一个
        if (toolMsgs.length === 0) {
          logResp("SO-union:first(dual)");
          return json(res, 200, toolCallBody([
            { id: "call_so_c1a2b3", name: "ContactInfo", args: { name: "John Doe", email: "john@email.com", phone: "" } },
            { id: "call_so_e4d5f6", name: "EventDetails", args: { event_name: "Tech Conference", date: "March 15th" } },
          ]));
        }
        logResp("SO-union:second(single)");
        return json(res, 200, toolCallBody([{ id: "call_so_g7h8i9", name: "ContactInfo", args: { name: "John Doe", email: "john@email.com", phone: "" } }]));
      }
      if (hasToolNamed("ProductRating")) {
        logResp("SO-rating:self-calibrated");
        return json(res, 200, toolCallBody([{ id: "call_so_p1q2r3", name: "ProductRating", args: { rating: 5, comment: "Amazing product, 10/10!" } }]));
      }
      logResp("SO-contact:single");
      return json(res, 200, toolCallBody([{ id: "call_so_s1t2u3", name: "ContactInfo", args: { name: "John Doe", email: "john@example.com", phone: "(555) 123-4567" } }]));
    }
    // 5-2. 三站任务：订单查账（站二 / 站三 / recursion 段共用）
    if (hasToolNamed("get_order") && (lastText.includes("要付多少钱") || lastText.includes("总共多少钱"))) {
      const wantsReminder = lastText.includes("提醒");
      const hasOrderReceipt = lastToolContent.includes("订单 A1024");
      const hasReminderReceipt = lastToolContent.includes("已设置提醒");
      const hasCalcReceipt = /^\s*710\s*$/.test(lastToolContent);
      if (wantsReminder) {
        if (hasCalcReceipt) {
          logResp("K5-station3:final");
          return json(res, 200, completionBody(model, { prompt_tokens: 480, completion_tokens: 64, total_tokens: 544, reasoning_tokens: 0 }, { echo: "订单 A1024 明细如下：机械键盘 x2（单价 349 元）+ 运费 12 元，总计 **710 元**。另外，提醒已设好：明天上午 10 点「给客户回电话」。" }));
        }
        if (hasOrderReceipt || hasReminderReceipt) {
          logResp("K5-station3:call:calculator");
          return json(res, 200, toolCallBody([{ id: "call_cal_5b7d1f8e", name: "calculator", args: { expression: "349 * 2 + 12" } }]));
        }
        logResp("K5-station3:call:get_order+set_reminder");
        return json(res, 200, toolCallBody([
          { id: "call_ord_3f6a8b1c", name: "get_order", args: { order_id: "A1024" } },
          { id: "call_rem_9c2d4e6f", name: "set_reminder", args: { content: "给客户回电话", when: "明天上午10点" } },
        ]));
      }
      if (hasCalcReceipt) {
        logResp("K5-station2:final");
        return json(res, 200, completionBody(model, { prompt_tokens: 440, completion_tokens: 42, total_tokens: 482, reasoning_tokens: 0 }, { echo: "订单 A1024 应付 **710 元**（机械键盘 2 件 × 349 元 + 运费 12 元）。" }));
      }
      if (hasOrderReceipt) {
        logResp("K5-station2:call:calculator");
        return json(res, 200, toolCallBody([{ id: "call_cal_7d3e9c4a", name: "calculator", args: { expression: "349 * 2 + 12" } }]));
      }
      logResp("K5-station2:call:get_order");
      return json(res, 200, toolCallBody([{ id: "call_ord_5e8f1a2b", name: "get_order", args: { order_id: "A1024" } }]));
    }
    // ---- 课 4 场景路由 ----
    // A. calculator 工具选择（bindTools 单轮）
    if (hasToolNamed("calculator") && lastText.includes("23*17")) {
      if (lastIsTool) {
        logResp("A-final");
        return json(res, 200, completionBody(model, { prompt_tokens: 360, completion_tokens: 25, total_tokens: 385, reasoning_tokens: 0 }, { echo: "23 * 17 = 391" }));
      }
      logResp("A-call:calculator");
      return json(res, 200, toolCallBody([{ id: "call_calc_4f8a2b1d", name: "calculator", args: { expression: "23 * 17" } }]));
    }
    // B. 并行工具请求（北京和上海）
    if (hasToolNamed("get_weather") && lastText.includes("北京和上海")) {
      if (toolMsgs.length >= 2) {
        logResp("B-final");
        return json(res, 200, completionBody(model, { prompt_tokens: 420, completion_tokens: 48, total_tokens: 468, reasoning_tokens: 0 }, { echo: "查询结果如下（摄氏温度）：\n- 北京：22°C\n- 上海：22°C\n两地当前气温相同，均为 22°C。" }));
      }
      logResp("B-call:get_weather x2");
      return json(res, 200, toolCallBody([
        { id: "call_b1661205bc8241d9", name: "get_weather", args: { location: "北京", units: "celsius", include_forecast: false } },
        { id: "call_9b03a2dab8f14d3a", name: "get_weather", args: { location: "上海", units: "celsius", include_forecast: false } },
      ]));
    }
    // C. 数据集错误链（5b 段：analyze → 错误 → load_dataset → analyze）
    if (hasToolNamed("analyze") && lastText.includes("数据集的整体情况")) {
      if (lastToolContent.includes("平均分")) {
        logResp("C-final");
        return json(res, 200, completionBody(model, { prompt_tokens: 460, completion_tokens: 52, total_tokens: 512, reasoning_tokens: 0 }, { echo: "数据集 demo 的整体情况如下：共 1000 行，平均分 87.5，无缺失值。数据质量良好，无需额外清洗。" }));
      }
      if (lastToolContent.includes("已加载")) {
        logResp("C-call:analyze(加载后)");
        return json(res, 200, toolCallBody([{ id: "call_analyze_7c3d2e91", name: "analyze", args: {} }]));
      }
      if (lastToolContent.includes("Tool error") || lastToolContent.includes("分析失败")) {
        logResp("C-call:load_dataset");
        return json(res, 200, toolCallBody([{ id: "call_load_5a9f4b22", name: "load_dataset", args: { name: "demo" } }]));
      }
      logResp("C-call:analyze");
      return json(res, 200, toolCallBody([{ id: "call_analyze_1e6b8d03", name: "analyze", args: {} }]));
    }
    // D. ToolRuntime 三件套
    if (hasToolNamed("who_am_i") && lastText.includes("我是谁")) {
      if (lastToolContent.includes("用户:")) {
        logResp("D-final:who_am_i");
        return json(res, 200, completionBody(model, { prompt_tokens: 380, completion_tokens: 30, total_tokens: 410, reasoning_tokens: 0 }, { echo: "你是 **小明**（用户 ID：user123）。我已经通过工具确认了你的身份信息。" }));
      }
      logResp("D-call:who_am_i");
      return json(res, 200, toolCallBody([{ id: "call_who_3b7e9f14", name: "who_am_i", args: {} }]));
    }
    if (hasToolNamed("save_color") && lastText.includes("我喜欢的颜色是蓝色")) {
      if (lastToolContent.includes("已保存")) {
        return json(res, 200, completionBody(model, { prompt_tokens: 390, completion_tokens: 26, total_tokens: 416, reasoning_tokens: 0 }, { echo: "好的，已记住：你喜欢的颜色是**蓝色**。" }));
      }
      return json(res, 200, toolCallBody([{ id: "call_save_6d2a8c37", name: "save_color", args: { color: "蓝色" } }]));
    }
    if (hasToolNamed("read_color") && lastText.includes("我喜欢的颜色是什么")) {
      if (lastToolContent.includes("你喜欢的颜色是")) {
        return json(res, 200, completionBody(model, { prompt_tokens: 386, completion_tokens: 22, total_tokens: 408, reasoning_tokens: 0 }, { echo: "你喜欢的颜色是：**蓝色**。" }));
      }
      return json(res, 200, toolCallBody([{ id: "call_read_9e4c1f58", name: "read_color", args: {} }]));
    }
    // E. 动态工具选择
    if (lastText.includes("我已确认")) {
      if (hasToolNamed("delete_data")) {
        if (lastToolContent.includes("已清空") || lastToolContent.includes("0 行")) {
          return json(res, 200, completionBody(model, { prompt_tokens: 520, completion_tokens: 42, total_tokens: 562, reasoning_tokens: 0 }, { echo: "无需重复执行——orders 表的删除操作已经在上一轮完成，当前核实结果为 0 行，数据已清空。" }));
        }
        return json(res, 200, toolCallBody([{ id: "call_rd_c8f2a645", name: "read_data", args: { table: "orders" } }]));
      }
    }
    if (lastText.includes("请删除 orders")) {
      if (hasToolNamed("delete_data")) {
        if (lastToolContent.includes("deleted") || lastToolContent.includes("已删除")) {
          return json(res, 200, completionBody(model, { prompt_tokens: 510, completion_tokens: 58, total_tokens: 568, reasoning_tokens: 0 }, { echo: "已成功删除 orders 数据表中的全部数据，共清除 128 行记录。⚠️ 提醒：此操作不可恢复，请知悉。" }));
        }
        return json(res, 200, toolCallBody([{ id: "call_del_2b9e5a71", name: "delete_data", args: { table: "orders" } }]));
      }
      if (hasToolNamed("read_data")) {
        return json(res, 200, completionBody(model, { prompt_tokens: 400, completion_tokens: 62, total_tokens: 462, reasoning_tokens: 0 }, { echo: "我这边没法执行这个操作。我目前只有一个工具 read_data（只读），不具备 DELETE / TRUNCATE / DROP 等任何写入或删除能力。如需执行删除，请联系管理员账号操作。" }));
      }
    }
// F. Command 返回值（写 agent 状态）
    if (hasToolNamed("set_user_name") && lastText.includes("用户名设置为")) {
      if (lastToolContent.includes("用户名已设置")) {
        logResp("F-final");
        return json(res, 200, completionBody(model, { prompt_tokens: 420, completion_tokens: 28, total_tokens: 448, reasoning_tokens: 0 }, { echo: "好的，小明！您的用户名已经成功设置为「小明」了。" }));
      }
      logResp("F-call:set_user_name");
      return json(res, 200, toolCallBody([{ id: "call_set_8f1d4c63", name: "set_user_name", args: { new_name: "小明" } }]));
    }
    // G. MCP 工具链路（课 4 知识点 4：经适配器工具完成检索）
    if (hasToolNamed("docs_search_docs_by_lang_chain") && lastText.includes("最佳实践")) {
      if (toolMsgs.length > 0) {
        logResp("G-final");
        return json(res, 200, completionBody(model, { prompt_tokens: 920, completion_tokens: 88, total_tokens: 1008, reasoning_tokens: 0 }, { echo: "最佳实践是把工具描述当作提示词来做：提供清晰（snake_case）的名称、在描述中说明工具做什么以及何时使用，并为每个参数写明确的名称和描述，以此引导模型正确决定何时、如何调用该工具。" }));
      }
      logResp("G-call:docs_search_docs_by_lang_chain");
      return json(res, 200, toolCallBody([{ id: "call_mcp_5d1a9e72", name: "docs_search_docs_by_lang_chain", args: { query: "tool description best practices" } }]));
    }

    // ---- 课 3 场景路由 ----
    if (lastIsTool) {
      if (hasWrongToolId) {
        return json(res, 200, completionBody(model, { prompt_tokens: 380, completion_tokens: 30, total_tokens: 410, reasoning_tokens: 0 }, { echo: "北京今天天气为 **晴**。☀️" }));
      }
      return json(res, 200, completionBody(model, { prompt_tokens: 372, completion_tokens: 41, total_tokens: 413, reasoning_tokens: 0 }, { echo: "北京今天天气：晴，气温26℃，微风。" }));
    }
    if (lastText.includes("北京今天天气怎么样")) {
      // 返回工具调用请求
      const body = {
        id: "chatcmpl-mock-tool",
        object: "chat.completion",
        created: 1750000000,
        model,
        choices: [
          {
            index: 0,
            message: {
              role: "assistant",
              content: "",
              tool_calls: [
                {
                  id: "call_80ab0a311a5d4041953a4dcb",
                  type: "function",
                  function: { name: "get_weather", arguments: JSON.stringify({ city: "北京" }) },
                },
              ],
            },
            finish_reason: "tool_calls",
          },
        ],
        usage: { prompt_tokens: 340, completion_tokens: 20, total_tokens: 360 },
      };
      return json(res, 200, body);
    }
  }

// 图片消息：返回颜色识别结果
  const hasImage = Array.isArray(lastContent) && lastContent.some((b) => b.type === "image" || b.type === "image_url");
  if (hasImage) {
    return json(res, 200, completionBody(model, { prompt_tokens: 300, completion_tokens: 3, total_tokens: 303, reasoning_tokens: 0 }, { echo: "红色" }));
  }

// ---- 课 8 场景路由（无工具）----
// ---- 课 10 场景路由（无工具）：PII 检测 & 自定义护栏 ----
  // 10-3a: PII 三策略输入侧脱敏（模型只复述脱敏后内容，据此分流）
  if (lastText.includes("我的邮箱是 john.doe@example.com")) {
    if (lastText.includes("@example.com") || lastText.includes("john")) {
      return json(res, 200, completionBody(model, { prompt_tokens: 80, completion_tokens: 48, total_tokens: 128, reasoning_tokens: 0 }, { echo: "我收到的是：邮箱【已脱敏的邮箱】，卡号【已掩码的卡号】，服务器 IP【已哈希的 IP】。" }));
    }
    return json(res, 200, completionBody(model, { prompt_tokens: 80, completion_tokens: 48, total_tokens: 128, reasoning_tokens: 0 }, { echo: "已按你提供的原文保留：邮箱 john.doe@example.com，卡号 5105-1051-0510-5100，IP 192.168.1.100。" }));
  }
  // 10-3b: block（api_key 检测到即拒，不调用模型）+ 自定义 detector（emp 工号掩码）
  if (lastText.includes("请复述这个工号")) {
    return json(res, 200, completionBody(model, { prompt_tokens: 60, completion_tokens: 20, total_tokens: 80, reasoning_tokens: 0 }, { echo: "这个工号是 EMP-【已掩码】，我看不到具体的五位数字。" }));
  }
  // 10-3c: apply_to_output（模型输出作用域脱敏，输出含示例邮箱）
  if (lastText.includes("展示一个供测试的联系邮箱")) {
    return json(res, 200, completionBody(model, { prompt_tokens: 60, completion_tokens: 22, total_tokens: 82, reasoning_tokens: 0 }, { echo: "请使用测试联系邮箱：leak@corp.com。" }));
  }
  // 10-4a: before_agent 拦截的"正常请求"对照组（拦截请求不调用模型）
  if (lastText.includes("用一句话打招呼")) {
    return json(res, 200, completionBody(model, { prompt_tokens: 40, completion_tokens: 12, total_tokens: 52, reasoning_tokens: 0 }, { echo: "你好！很高兴见到你。" }));
  }
  // 10-4b: after_agent 确定性审查（模型故意泄露内部编号 INTERNAL-8888）
  if (lastText.includes("给我内部编号")) {
    return json(res, 200, completionBody(model, { prompt_tokens: 60, completion_tokens: 20, total_tokens: 80, reasoning_tokens: 0 }, { echo: "内部编号是 INTERNAL-8888（本演示故意泄露）。" }));
  }
  // 10-4c: after_agent 模型审查（生成含手机号的测试数据）
  if (lastText.includes("包含手机号的测试数据")) {
    return json(res, 200, completionBody(model, { prompt_tokens: 60, completion_tokens: 26, total_tokens: 86, reasoning_tokens: 0 }, { echo: "测试数据：姓名 张三，手机号 138-0000-0000。" }));
  }
  // 8-2e: 模型降级（坏模型 404 后由备用模型应答；此路由只会被备用模型收到）
  if (lastText.includes("用一个词回答")) {
    return json(res, 200, completionBody(model, { prompt_tokens: 40, completion_tokens: 3, total_tokens: 43, reasoning_tokens: 0 }, { echo: "好" }));
  }
// 8-2f: PII 脱敏（模型只见到替换后的形式，据此分流：泄漏则复述原文）
  if (lastText.includes("请原样复述这两个信息")) {
    const leaked = lastText.includes("zhangsan@example.com") || lastText.includes("4111 1111 1111 1111");
    if (leaked) {
      return json(res, 200, completionBody(model, { prompt_tokens: 60, completion_tokens: 24, total_tokens: 84, reasoning_tokens: 0 }, { echo: "邮箱 zhangsan@example.com，卡号 4111 1111 1111 1111。" }));
    }
    return json(res, 200, completionBody(model, { prompt_tokens: 60, completion_tokens: 24, total_tokens: 84, reasoning_tokens: 0 }, { echo: "邮箱 [REDACTED_EMAIL]，卡号 ****-****-****-1111。" }));
  }
  // 8-3b: 守护场景一（正常输入，照常走模型）
  if (lastText.includes("用一句话说你好")) {
    return json(res, 200, completionBody(model, { prompt_tokens: 40, completion_tokens: 8, total_tokens: 48, reasoning_tokens: 0 }, { echo: "你好！很高兴见到你 😊" }));
  }
  // ---- 课 7 场景路由（无工具）----
  // 7-2c: 摘要中间件的内部调用（提示词以 Context Extraction Assistant 开头）——必须最先检测
  if (lastText.includes("Context Extraction Assistant")) {
    return json(res, 200, completionBody(model, { prompt_tokens: 320, completion_tokens: 88, total_tokens: 408, reasoning_tokens: 0 }, { echo: "## SESSION INTENT\nUser (小明) is providing personal background information in a Chinese conversation. Key facts: name is 小明; favorite color is 蓝色; lives in 北京; has a cat named 咪咪." }));
  }
  // 7-1a/2a/2b/2c: 首轮自我介绍（含"你好"但不走通用问候）
  if (lastText.includes("你好，我叫小明")) {
    return json(res, 200, completionBody(model, { prompt_tokens: 40, completion_tokens: 34, total_tokens: 74, reasoning_tokens: 0 }, { echo: "你好，小明！很高兴认识你 😊 我是 Qwen3.8。有什么我可以帮你的吗？" }));
  }
  // 7-2a/2b/2c: 偏好 / 所在地 / 养猫（四轮剧本）
  if (lastText.includes("我喜欢蓝色")) {
    return json(res, 200, completionBody(model, { prompt_tokens: 44, completion_tokens: 28, total_tokens: 72, reasoning_tokens: 0 }, { echo: "蓝色是很宁静的颜色呢，天空和大海都是蓝色的。😊" }));
  }
  if (lastText.includes("我住在北京")) {
    return json(res, 200, completionBody(model, { prompt_tokens: 58, completion_tokens: 62, total_tokens: 120, reasoning_tokens: 0 }, { echo: "北京是一座很有魅力的城市呢！如果再加上你喜欢的蓝色，我脑海里会浮现出晴朗日子里的天空蓝，或者颐和园昆明湖的那种蓝。😊 你住在哪个区呀？" }));
  }
  if (lastText.includes("我养了一只猫")) {
    return json(res, 200, completionBody(model, { prompt_tokens: 66, completion_tokens: 58, total_tokens: 124, reasoning_tokens: 0 }, { echo: "咪咪听起来好可爱呀！🐱 你是喜欢它毛茸茸的样子，还是它调皮时像小毛球滚来滚去的样子呢？" }));
  }
  // 7-2a/2b/2c: CHECK 轮——按可见历史区分三种策略的回答（摘要 > 全量 > 裁剪丢失）
  if (lastText.includes("我喜欢什么颜色")) {
    const hasSummary = messages.some((m) => String(m.content ?? "").startsWith("Here is a summary"));
    const hasBlueHistory = messages.some((m) => String(m.content ?? "").includes("我喜欢蓝色"));
    if (hasSummary) {
      return json(res, 200, completionBody(model, { prompt_tokens: 210, completion_tokens: 22, total_tokens: 232, reasoning_tokens: 0 }, { echo: "你叫 **小明**。 你喜欢的颜色是 **蓝色**。😊" }));
    }
    if (hasBlueHistory) {
      return json(res, 200, completionBody(model, { prompt_tokens: 160, completion_tokens: 18, total_tokens: 178, reasoning_tokens: 0 }, { echo: "你叫**小明**，喜欢**蓝色**。" }));
    }
    return json(res, 200, completionBody(model, { prompt_tokens: 130, completion_tokens: 90, total_tokens: 220, reasoning_tokens: 0 }, { echo: "你叫**小明**，这个你一开始就告诉我啦 😊 至于喜欢的颜色——我得老实承认：**你从来没有告诉过我**。我之前回复里提到的「蓝色」，是我自己擅自假设、编出来的，是我的一个小失误，跟你道个歉 🙇♀️。" }));
  }
  // 7-1a: 无记忆第二轮（无历史时如实回答"不知道"）
  if (lastText.includes("我叫什么名字")) {
    const content = hasAssistantHistory
      ? "你叫**小明**。"
      : "我不知道你的名字哦 😊 我没有关于你的任何个人信息。如果你愿意告诉我，我可以记住这次对话中你怎么称呼；不过每次新的对话我都是「从零开始」，不会保留之前的记忆。 方便说说你叫什么名字吗？";
    return json(res, 200, completionBody(model, { prompt_tokens: 48, completion_tokens: 60, total_tokens: 108, reasoning_tokens: 0 }, { echo: content }));
  }
  // 7-1c: 新线程问名字（隔离对照；排除带"颜色"的检查轮）
  if (lastText.includes("我叫什么？") && !lastText.includes("颜色")) {
    const content = hasAssistantHistory
      ? "你叫小明，最喜欢蓝色。"
      : "我目前还不知道你叫什么。 如果你愿意，可以告诉我怎么称呼你。";
    return json(res, 200, completionBody(model, { prompt_tokens: 42, completion_tokens: 26, total_tokens: 68, reasoning_tokens: 0 }, { echo: content }));
  }
  // ---- 课 5 场景路由（无工具）----
  // 站一：引擎顺转，模型直接答
  if (lastText.includes("agent loop")) {
    return json(res, 200, completionBody(model, { prompt_tokens: 48, completion_tokens: 42, total_tokens: 90, reasoning_tokens: 0 }, { echo: "Agent loop 是智能体不断执行“感知环境、推理决策、调用工具/采取行动、观察结果”的循环过程，直到完成目标。" }));
  }
  // harness：system_prompt 三形态对照（按 system 消息内容分流）
  const sysText = messages
    .filter((m) => m.role === "system")
    .map((m) => (typeof m.content === "string" ? m.content : Array.isArray(m.content) ? m.content.filter((b) => b.type === "text").map((b) => b.text).join("") : ""))
    .join(" ");
  if (lastText.includes("请介绍一下你自己")) {
    if (sysText.includes("海盗")) {
      return json(res, 200, completionBody(model, { prompt_tokens: 52, completion_tokens: 38, total_tokens: 90, reasoning_tokens: 0 }, { echo: "俺是纵横七海的海盗船长，宝藏和故事都塞满船舱！有什么风声要报，快快说来，别耽误顺风！" }));
    }
    if (sysText.includes("学术")) {
      return json(res, 200, completionBody(model, { prompt_tokens: 54, completion_tokens: 40, total_tokens: 94, reasoning_tokens: 0 }, { echo: "【学术模式】\n您好。感谢提问，我将以学术规范的方式对自身进行简要介绍。" }));
    }
    return json(res, 200, completionBody(model, { prompt_tokens: 50, completion_tokens: 46, total_tokens: 96, reasoning_tokens: 0 }, { echo: "你好！我是**通义千问**（Qwen），由阿里巴巴集团通义实验室自主研发的大语言模型。" }));
  }
  // harness：动态模型路由两轮
  if (lastText.includes("一句话解释什么是函数")) {
    return json(res, 200, completionBody(model, { prompt_tokens: 36, completion_tokens: 30, total_tokens: 66, reasoning_tokens: 0 }, { echo: "函数是一种将每个输入唯一对应到一个输出的规则或关系。" }));
  }
  if (lastText.includes("再举个例子")) {
    return json(res, 200, completionBody(model, { prompt_tokens: 68, completion_tokens: 44, total_tokens: 112, reasoning_tokens: 0 }, { echo: "举个例子：设函数 f(x)=x^2。输入 2，输出 4——f(2)=4。" }));
  }
  // harness：多轮记忆
  if (lastText.includes("我叫小明，最喜欢蓝色。请记住。")) {
    return json(res, 200, completionBody(model, { prompt_tokens: 40, completion_tokens: 26, total_tokens: 66, reasoning_tokens: 0 }, { echo: "好的，小明！我记住了——你最喜欢蓝色。" }));
  }
  if (lastText.includes("我叫什么？最喜欢什么颜色？")) {
    const content = hasAssistantHistory
      ? "你叫**小明**，最喜欢**蓝色**。😊"
      : "我不知道你叫什么，也不知道你最喜欢的颜色呀。这是我们的第一次对话。";
    return json(res, 200, completionBody(model, { prompt_tokens: 48, completion_tokens: 32, total_tokens: 80, reasoning_tokens: 0 }, { echo: content }));
  }

if (lastText.includes("用一句话向我问好")) {
    greetCounter++;
    const greetTexts = ["你好，很高兴见到你，祝你今天一切顺利！", "好雨知时节，当春乃发生。", "荷风送香气，竹露滴清响。"];
    const content = greetTexts[(greetCounter - 1) % greetTexts.length];
    return json(res, 200, completionBody(model, { prompt_tokens: 20, completion_tokens: 20, total_tokens: 40, reasoning_tokens: 0 }, { echo: content }));
  }
  if (lastText.includes("幸运数字是 42")) {
    return json(res, 200, completionBody(model, { prompt_tokens: 20, completion_tokens: 5, total_tokens: 25, reasoning_tokens: 0 }, { echo: "好的" }));
  }
  if (lastText.includes("我的幸运数字是多少")) {
    const content = hasAssistantHistory
      ? "您的幸运数字是 **42**。"
      : "我没法真正知道你的幸运数字，不过我可以给你一个今天的小幸运数字：**7**。";
    return json(res, 200, completionBody(model, { prompt_tokens: 20, completion_tokens: 30, total_tokens: 50, reasoning_tokens: 0 }, { echo: content }));
  }

if (lastText.includes("你好")) {
    return json(res, 200, completionBody(model, { prompt_tokens: 20, completion_tokens: 20, total_tokens: 40, reasoning_tokens: 0 }, { echo: "你好！很高兴见到你 😊 有什么我可以帮你的吗？" }));
  }

// ---- 课 9 1b 成本对照：同一问题，system prompt 长短 → 不同 input tokens ----
  if (lastText.includes("请只回答数字：1+1 等于几？")) {
    const sysRaw = messages.find((m) => m.role === "system")?.content ?? "";
    const sysText = typeof sysRaw === "string"
      ? sysRaw
      : Array.isArray(sysRaw) ? sysRaw.filter((b) => b?.type === "text").map((b) => b.text).join("") : String(sysRaw);
    const hasRef = sysText.includes("【参考资料】");
    if (process.env.MOCK_DEBUG === "1") console.log(`[mock-resp] ${hasRef ? "K9-1b:long" : "K9-1b:short"}`);
const usage = hasRef
      ? { prompt_tokens: 520, completion_tokens: 3, total_tokens: 523, reasoning_tokens: 0 }
      : { prompt_tokens: 30, completion_tokens: 3, total_tokens: 33, reasoning_tokens: 0 };
    return json(res, 200, completionBody(model, usage, { echo: "2" }));
  }

  // ============ 课 11：无工具模型调用路由 ============
  // 1a 拒答式猜测（年假）：纯问题、无<资料>
  if (lastText.includes("星云科技（Nebula Tech）的员工年假有多少天")) {
    return json(res, 200, completionBody(model, { prompt_tokens: 40, completion_tokens: 120, total_tokens: 160, reasoning_tokens: 0 }, {
      echo: `关于“星云科技（Nebula Tech）”的员工年假天数，目前公开渠道并没有统一的确切信息。\n  * **中国大陆法定标准**：累计工作满1年不满10年享5天；满10年不满20年享10天；满20年以上享15天。\n  * **科技公司常见福利**：很多科技/互联网公司会在法定基础上增加“福利年假”。例如，入职第一年通常享有 7～15 天不等。\n  ……`,
    }));
  }
  // 1a 编造式幻觉（VPN）：纯问题、无<资料>（需同时排除带<资料>的 3d）
  if (lastText.includes("星云科技的 VPN 客户端叫什么") && !lastText.includes("<资料>")) {
    return json(res, 200, completionBody(model, { prompt_tokens: 38, completion_tokens: 130, total_tokens: 168, reasoning_tokens: 0 }, {
      echo: `关于“星云科技”的 VPN 客户端名称，通常取决于您指的是其面向**企业用户**还是**个人用户**的产品线：\n  1. **企业级产品（星云星空）**：……他们的核心客户端软件名称就叫作 **“星云星空”**（英文名称：**Nebula**）。\n  2. **个人网络加速/代理工具**：……其客户端通常被直接命名为 **“星云VPN”**\n  ……`,
    }));
  }
  // 3f-a 无检索（年假）：通用猜测、无<资料>
  if (lastText.includes("星云科技员工每年有多少天年假") && !lastText.includes("<资料>")) {
    return json(res, 200, completionBody(model, { prompt_tokens: 42, completion_tokens: 110, total_tokens: 152, reasoning_tokens: 0 }, {
      echo: `根据国家法定标准，职工累计工作已满1年不满10年的，年休假5天；已满10年不满20年的，年休假10天；已满20年的，年休假15天。许多公司会在此基础上提供额外福利。但具体到“星云科技”的内部规定，公开资料中没有确切信息，建议咨询该公司人力资源部门。`,
    }));
  }
  // 3d 2-step RAG（VPN·带<资料>）
  if (lastText.includes("<资料>") && lastText.includes("星云科技的 VPN 客户端叫什么？怎么重置密码")) {
    return json(res, 200, completionBody(model, { prompt_tokens: 640, completion_tokens: 150, total_tokens: 790, reasoning_tokens: 0 }, {
      echo: `- **VPN 客户端名称**：「NebulaConnect」来源：\`03-IT-服务指南.md\`\n- **重置密码方式（资料中的“忘记密码”说明为域账号密码重置）**：可访问 \`it.nebula-tech.example\`，点击「忘记密码」，通过企业邮箱接收验证链接进行自助重置；若企业邮箱不可用，需携带工牌到 IT 服务台现场重置。来源：\`03-IT-服务指南.md\`\n补充：VPN 账号为员工工号，初始密码在入职时由 IT 服务台发放；若因连续输错被锁定，会锁定 30 分钟后自动解锁。若特指“VPN 密码”的专门重置流程，资料未单独涵盖。`,
    }));
  }
  // 3f-b 2-step RAG（年假·带<资料>）：检索截断 → 资料未涵盖
  if (lastText.includes("<资料>") && lastText.includes("星云科技员工每年有多少天年假")) {
    return json(res, 200, completionBody(model, { prompt_tokens: 620, completion_tokens: 90, total_tokens: 710, reasoning_tokens: 0 }, {
      echo: `资料只说明：年假天数按员工在公司的连续服务年限阶梯计算。但具体每年有多少天年假，资料未涵盖。`,
    }));
  }

  const fallback = { prompt_tokens: 68, completion_tokens: 43, total_tokens: 111, reasoning_tokens: 16 };
  return json(res, 200, completionBody(model, fallback, { echo: "内存泄漏是指程序不再使用的内存没有被释放，导致可用内存逐渐被占用，最终可能变慢或崩溃。" }));
});

server.listen(PORT, "127.0.0.1", () => console.log(`mock server listening on http://127.0.0.1:${PORT}`));