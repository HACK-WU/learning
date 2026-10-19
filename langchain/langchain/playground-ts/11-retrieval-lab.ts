/**
 * 第 11 课 · Retrieval 检索与 RAG 实验（TypeScript 版，对应 playground/11-retrieval-lab.py）
 *
 * 运行（在 playground-ts 目录内，模型与嵌入均连本地 mock 端点采集证据）：
 *
 *     BAILIAN_BASE_URL=http://127.0.0.1:8931/v1 BAILIAN_API_KEY=mock \
 *     npx tsx 11-retrieval-lab.ts
 *
 * 设计 3 大板块（对应 3 个知识点，与 Python 侧脚本一一对应）：
 * 1. 为什么需要检索：私有知识直问（无检索）的两种失败模式——诚实猜测与幻觉编造
 * 2. 知识库构建链路：加载 → 切分（三档对照）→ 块结构 → 嵌入（维度/批量/截维）→ 入库
 * 3. 检索器与 RAG 架构：三种查询方式 / Retriever 三形态 / 自定义链 /
 *    2-step RAG / Agentic RAG / 三方对照 / 跨文档复合问题
 *
 * 说明：脚本输出即讲义引用的实测证据，请勿修改后当作新结果引用。
 *       TS 侧与 Python 侧的 API 形态差异（本脚本实测确认）：
 *         - 无 @chain 装饰器 → 手写 Promise 函数；batch 用 Promise.all 模拟
 *         - 无 InMemoryVectorStore 现成实现 → 基于 @langchain/core 的 VectorStore
 *           抽象基类自实现内存向量库（余弦相似度，越大越相似，与 Python 对齐）
 *         - VectorStoreRetriever 的 search_type 仅实现 similarity / mmr 两种；
 *           similarity_score_threshold 不报错、退化为 similarity（与 Python 抛
 *           NotImplementedError 形成差异，见 3b）
 *         - addStartIndex 产生的 metadata 字段是 loc.lines（Python 为 start_index）
 *         - 嵌入走本地 mock /embeddings 端点（确定性、4096 维，支持 dimensions 截维），
 *           无真实 SiliconFlow key 也可复现分数与排序
 *         - @tool 用 zod schema 声明参数（Python 为函数注解）
 */
import * as z from "zod";
import dotenv from "dotenv";
import { readdirSync, readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { randomUUID } from "node:crypto";
import { Document } from "@langchain/core/documents";
import { VectorStore } from "@langchain/core/vectorstores";
import { OpenAIEmbeddings } from "@langchain/openai";
import { RecursiveCharacterTextSplitter } from "@langchain/textsplitters";
import { tool, createAgent, initChatModel } from "langchain";

dotenv.config({ path: [".env", "../playground/.env"] });

const API_KEY = process.env.BAILIAN_API_KEY;
const BASE_URL = process.env.BAILIAN_BASE_URL;
const SILICONFLOW_MODEL = process.env.SILICONFLOW_EMBEDDING_MODEL ?? "Qwen/Qwen3-Embedding-8B";
// 采集证据时连本地 mock 的 /embeddings（确定性向量，可复现分数）；生产为真实 SiliconFlow 地址
const EMBED_BASE_URL = process.env.MOCK_EMBED_URL ?? "http://127.0.0.1:8931/v1";

const model = await initChatModel("qwen3.8-flash", {
  modelProvider: "openai",
  apiKey: API_KEY,
  baseUrl: BASE_URL,
  maxRetries: 2,
  timeout: 60_000,
});

const embeddings = new OpenAIEmbeddings({
  model: SILICONFLOW_MODEL,
  apiKey: process.env.SILICONFLOW_API_KEY ?? "mock",
  configuration: { baseURL: EMBED_BASE_URL },
  timeout: 60_000,
  stripNewLines: false,
});

// ============ 自实现内存向量库（基于 VectorStore 抽象基类）============
// 余弦相似度，返回越大越相似（与 Python 侧 InMemoryVectorStore 对齐）
type Doc = Document<Record<string, any>>;

class MiniMemoryVectorStore extends VectorStore {
  FilterType = {};

  private vectors: number[][] = [];
  private docs: Doc[] = [];
  private ids: string[] = [];

_vectorstoreType(): string {
    return "mini_memory";
  }

  get size(): number {
    return this.vectors.length;
  }

  async addVectors(vectors: number[][], documents: Doc[]): Promise<string[]> {
    const createdIds = documents.map(() => randomUUID());
    for (let i = 0; i < documents.length; i++) {
      this.vectors.push(vectors[i] ?? []);
      this.docs.push(documents[i]);
      this.ids.push(createdIds[i]);
    }
    return createdIds;
  }

async addDocuments(documents: Doc[]): Promise<string[]> {
    const texts = documents.map((d) => d.pageContent);
    const vectors = await this.embeddings.embedDocuments(texts);
    return this.addVectors(vectors, documents);
  }

  async similaritySearchVectorWithScore(query: number[], k: number): Promise<[Doc, number][]> {
    const cos = (a: number[], b: number[]) => {
      let dot = 0, na = 0, nb = 0;
      for (let i = 0; i < a.length; i++) { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i]; }
      const denom = Math.sqrt(na) * Math.sqrt(nb);
      return denom === 0 ? 0 : dot / denom;
    };
    return this.vectors
      .map((v, i) => [this.docs[i], cos(query, v)] as [Doc, number])
      .sort((a, b) => b[1] - a[1])
      .slice(0, k);
  }

  // MMR：先取 fetchK 相似候选，再按「相似 − lambda × 已选最大相似」贪心选择 k 个
  async maxMarginalRelevanceSearch(
    query: string,
    options: { k?: number; fetchK?: number; lambda?: number }
  ): Promise<Doc[]> {
    const k = options.k ?? 4;
    const fetchK = options.fetchK ?? 20;
    const lambda = options.lambda ?? 0.5;
    const queryVec = await this.embeddings.embedQuery(query);
    const cos = (a: number[], b: number[]) => {
      let dot = 0, na = 0, nb = 0;
      for (let i = 0; i < a.length; i++) { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i]; }
      const denom = Math.sqrt(na) * Math.sqrt(nb);
      return denom === 0 ? 0 : dot / denom;
    };
    const candidates = this.vectors
      .map((v, i) => ({ vec: v, doc: this.docs[i], sim: cos(queryVec, v) }))
      .sort((a, b) => b.sim - a.sim)
      .slice(0, fetchK);

    const picked: typeof candidates = [];
    const pickedIdx = new Set<number>();
    for (let pass = 0; pass < k && picked.length < candidates.length; pass++) {
      let best = -Infinity;
      let bestIdx = -1;
      for (let i = 0; i < candidates.length; i++) {
        if (pickedIdx.has(i)) continue;
        let maxSimToPicked = 0;
        for (const p of picked) maxSimToPicked = Math.max(maxSimToPicked, cos(candidates[i].vec, p.vec));
        const mmrScore = lambda * candidates[i].sim - (1 - lambda) * maxSimToPicked;
        if (mmrScore > best) { best = mmrScore; bestIdx = i; }
      }
      picked.push(candidates[bestIdx]);
      pickedIdx.add(bestIdx);
    }
    return picked.map((p) => p.doc);
  }
}

// ============ 输出辅助 ============
function section(title: string) {
  console.log(`\n${"=".repeat(16)} ${title} ${"=".repeat(16)}`);
}

function brief(content: unknown, limit = 300): string {
  const text = content == null ? "" : String(content);
  return text.replace(/\s+/g, " ").trim().slice(0, limit);
}

async function exp(label: string, fn: () => Promise<void> | void) {
  console.log(`\n-- ${label} --`);
  const t0 = Date.now();
  try {
    await fn();
  } catch (e: any) {
    console.log(`  [失败] ${(e as Error)?.constructor?.name ?? typeName(e)}: ${String((e as Error)?.message ?? e).slice(0, 300)}`);
  }
  console.log(`  [本项耗时 ${((Date.now() - t0) / 1000).toFixed(1)}s]`);
}

function typeName(e: unknown): string {
  const c = (e as any)?.constructor?.name;
  return typeof c === "string" ? c : "Unknown";
}

function showChain(msgs: any[], limit = 80): void {
  msgs.forEach((m, i) => {
    const type: string = typeof m.getType === "function" ? m.getType() : (m.type ?? (m as any)?.constructor?.name);
    if (type === "ai" && m.tool_calls?.length) {
      const calls = m.tool_calls
        .map((tc: any) => `${tc.name}(${JSON.stringify(tc.args)})`)
        .join("; ");
      console.log(`    [${i}] ai -> 调用工具 ${calls}`);
    } else if (type === "tool") {
      console.log(`    [${i}] tool 返回: ${brief(m.content, limit)}`);
    } else if (type === "ai" && m.content) {
      console.log(`    [${i}] ai 最终回答: ${brief(m.content, 600)}`);
    } else {
      console.log(`    [${i}] ${type}: ${brief(m.content, 70)}`);
    }
  });
}

// ============ 知识库路径 ============
const KB_DIR = join(dirname(fileURLToPath(import.meta.url)), "../playground/kb");

function loadKbDocuments(): Doc[] {
  return readdirSync(KB_DIR)
    .filter((f) => f.endsWith(".md"))
    .sort()
    .map((f) => new Document({ pageContent: readFileSync(join(KB_DIR, f), "utf-8"), metadata: { source: f } }));
}

async function buildChunks(): Promise<Doc[]> {
  const sp = new RecursiveCharacterTextSplitter({
    chunkSize: 300,
    chunkOverlap: 60,
    addStartIndex: true,
  } as any);
  return sp.splitDocuments(loadKbDocuments());
}

// 全局共享 store（构建一次）
let GLOBAL_STORE: MiniMemoryVectorStore | null = null;
let GLOBAL_CHUNKS: Doc[] = [];

async function prepareStore(): Promise<MiniMemoryVectorStore> {
  if (!GLOBAL_STORE) {
    GLOBAL_CHUNKS = await buildChunks();
    GLOBAL_STORE = new MiniMemoryVectorStore(embeddings, {});
    await GLOBAL_STORE.addDocuments(GLOBAL_CHUNKS);
    console.log(`  [store 就绪：${GLOBAL_CHUNKS.length} 块]`);
  }
  return GLOBAL_STORE;
}

// ============ 实验 ============

// 站一：1a 无检索直问的两种失败模式
const PRIVATE_QS = [
  "星云科技（Nebula Tech）的员工年假有多少天？",
  "星云科技的 VPN 客户端叫什么？",
];

async function exp1a() {
  for (let i = 0; i < PRIVATE_QS.length; i++) {
    console.log(`  [问题 ${i + 1}] ${PRIVATE_QS[i]}`);
    const r = await model.invoke(PRIVATE_QS[i]);
    console.log(`  [回答 ${i + 1}] ${brief(r.content, 700)}`);
    console.log();
  }
}

function exp2a() {
  const docs = loadKbDocuments();
  console.log(`  文件数: ${docs.length}`);
  for (const d of docs) {
    console.log(`    ${d.metadata.source}: ${d.pageContent.length} 字符`);
  }
  const d0 = docs[0] as any;
  console.log(`  Document 字段: pageContent=${typeof d0.pageContent} / metadata=${d0.metadata?.constructor?.name} / id=${JSON.stringify(d0.id)}`);
}

async function exp2b() {
  const docs = loadKbDocuments();
  for (const [size, overlap] of [[200, 40], [300, 60], [400, 80]]) {
    const sp = new RecursiveCharacterTextSplitter({ chunkSize: size as number, chunkOverlap: overlap as number });
    const chunks = await sp.splitDocuments(docs);
    const lens = chunks.map((c) => c.pageContent.length);
    console.log(`  chunk_size=${String(size).padStart(4)} overlap=${String(overlap).padStart(3)} -> ${String(chunks.length).padStart(3)} 块 | 长度 min=${Math.min(...lens)} max=${Math.max(...lens)} avg=${Math.floor(lens.reduce((a, b) => a + b, 0) / lens.length)}`);
  }
  console.log(`  默认分隔符: ${JSON.stringify(new RecursiveCharacterTextSplitter({ chunkSize: 300 }).separators)}`);
}

async function exp2c() {
  const chunks = await buildChunks();
  console.log(`  共 ${chunks.length} 块；取第 2 块展示：`);
  const c = chunks[1];
  console.log(`  metadata: ${JSON.stringify(c.metadata)}`);
  console.log(`  内容（${c.pageContent.length} 字符）：`);
  for (const line of c.pageContent.split("\n").slice(0, 8)) {
    console.log(`    | ${line}`);
  }
}

async function exp2d() {
  const sample = [
    "年假天数按员工服务年限阶梯计算",
    "VPN 客户端为 NebulaConnect，账号为员工工号",
    "报销需在费用发生后 30 个自然日内提交",
  ];
  const t0 = Date.now();
  const vecs = await embeddings.embedDocuments(sample);
  const t1 = Date.now();
  console.log(`  embed_documents 批量 ${sample.length} 条: 每条 ${vecs[0].length} 维 | 耗时 ${((t1 - t0) / 1000).toFixed(1)}s`);
  const qv = await embeddings.embedQuery("年假有多少天");
  const head3 = qv.slice(0, 3).map((x) => Number(x.toFixed(5)));
  console.log(`  embed_query: ${qv.length} 维 | 前 3 位: [${head3.join(", ")}]`);
  const same = (await embeddings.embedDocuments(["年假有多少天"]))[0];
  const diff = qv.reduce((a, v, i) => a + Math.abs(v - same[i]), 0);
  console.log(`  embed_query 与 embed_documents 对同一文本: 向量差绝对值之和=${diff.toFixed(6)}（0 表示同一空间同一条路径）`);
  const emb2 = new OpenAIEmbeddings({
    model: SILICONFLOW_MODEL,
    apiKey: process.env.SILICONFLOW_API_KEY ?? "mock",
    configuration: { baseURL: EMBED_BASE_URL },
    dimensions: 1024,
    timeout: 60_000,
    stripNewLines: false,
  });
  const v2 = await emb2.embedQuery("年假有多少天");
  console.log(`  dimensions=1024 截维（MRL）: 实际返回 ${v2.length} 维`);
}

async function exp2e() {
  const chunks = await buildChunks();
  const store = new MiniMemoryVectorStore(embeddings, {});
  const t0 = Date.now();
  const ids = await store.addDocuments(chunks);
  const t1 = Date.now();
  console.log(`  add_documents: ${ids.length} 块入库 | 耗时 ${((t1 - t0) / 1000).toFixed(1)}s`);
console.log(`  返回 id 前 2 个: ${ids[0].slice(0, 18)}... / ${ids[1].slice(0, 18)}...`);
  console.log(`  store 内块数: ${store.size}`);
}

// ============ 站三 ============
async function exp3a() {
  const store = await prepareStore();
  const q = "年假有多少天";
  console.log(`  查询: ${q}`);
const r1 = await store.similaritySearch(q, 3);
  for (const d of r1) {
    console.log(`    [${d.metadata.source}] ${brief(d.pageContent.split("\n")[0], 44)}`);
  }
  console.log();
  const r2 = await store.similaritySearchWithScore(q, 3);
  console.log(`  [similarity_search_with_score] 分数方向验证:`);
  for (const [d, s] of r2) {
    console.log(`    score=${s.toFixed(4)} | [${d.metadata.source}] ${brief(d.pageContent.split("\n")[0], 40)}`);
  }
  const selfres = await store.similaritySearchWithScore("年假天数按员工在公司的连续服务年限阶梯计算", 1);
  const oddres = await store.similaritySearchWithScore("今天天气怎么样", 1);
  const sSelf = selfres[0][1], sOdd = oddres[0][1];
  console.log(`  对照: 原文查询 score=${sSelf.toFixed(4)} vs 无关查询 score=${sOdd.toFixed(4)}`);
  console.log(`  -> 结论: score 为余弦相似度（越大越相似）`);
  console.log();
  const qv = await embeddings.embedQuery(q);
  const r3 = await store.similaritySearchVectorWithScore(qv, 2);
  console.log(`  [similarity_search_by_vector] 用 ${qv.length} 维查询向量 -> ${r3.length} 条:`);
  for (const [d] of r3) {
    console.log(`    [${d.metadata.source}] ${brief(d.pageContent.split("\n")[0], 40)}`);
  }
}

async function exp3b() {
  const store = await prepareStore();
  const q = "远程办公";
  console.log(`  查询: ${q}`);
for (const st of ["similarity", "mmr"]) {
    const kwargs = st === "mmr" ? { k: 3, fetchK: 10, lambda: 0.5 } : { k: 3 };
    const rr = await store.asRetriever({ searchType: st as "similarity" | "mmr", searchKwargs: kwargs }).invoke(q);
    console.log(`  [as_retriever · ${st}] 返回 ${rr.length} 条:`);
    for (const d of rr) {
      console.log(`    [${d.metadata.source}] ${brief(d.pageContent.split("\n")[0], 42)}`);
    }
  }
  console.log();
// TS：VectorStoreRetriever 仅实现 similarity / mmr；threshold 退化为 similarity（不报错）
  try {
    const rr = await store.asRetriever({
      searchType: "similarity_score_threshold",
      searchKwargs: { scoreThreshold: 0.45 },
    } as any).invoke(q);
    console.log(`  [similarity_score_threshold] TS 侧退化为 similarity，返回 ${rr.length} 条（不抛错）`);
    for (const d of rr) {
      console.log(`    [${d.metadata.source}] ${brief(d.pageContent.split("\n")[0], 42)}`);
    }
  } catch (e: any) {
    console.log(`  [similarity_score_threshold] ${typeName(e)}: ${String((e as Error)?.message).slice(0, 120)}`);
  }
const pairs = await store.similaritySearchWithScore(q, 15);
  const kept = pairs.filter(([, s]) => s >= 0.05);
  console.log(`  替代方案（手动阈值过滤 ≥0.05，mock 标度）: ${pairs.length} 条中保留 ${kept.length} 条 ->`);
  for (const [d, s] of kept.slice(0, 3)) {
    console.log(`    score=${s.toFixed(4)} | [${d.metadata.source}] ${brief(d.pageContent.split("\n")[0], 40)}`);
  }
}

async function exp3c() {
  const store = await prepareStore();
  const custom = async (query: string) => store.similaritySearch(query, 2);
  const res = await Promise.all(["年假", "VPN 密码"].map(custom));
  console.log(`  自定义 retriever（Promise 链）| batch 返回 ${res.length} 组:`);
  for (const group of res) {
    console.log(`    组内 ${group.length} 条 | 首条: [${group[0].metadata.source}] ${brief(group[0].pageContent.split("\n")[0], 40)}`);
  }
}

const PROMPT_TEMPLATE = `你是星云科技的企业助手。请根据以下内部资料回答问题。

<资料>
{context}
</资料>

要求：
1. 只依据资料作答，并注明来源文件名；
2. 资料中没有的信息，如实说明「资料未涵盖」，不要编造。

问题：{question}`;

async function exp3d() {
  const store = await prepareStore();
  const q = "星云科技的 VPN 客户端叫什么？怎么重置密码？";
  const hits = await store.similaritySearch(q, 3);
  const context = hits
    .map((d) => `[来源: ${d.metadata.source}]\n${d.pageContent}`)
    .join("\n\n---\n\n");
  const prompt = PROMPT_TEMPLATE.replace("{context}", context).replace("{question}", q);
  const srcs = hits.map((d) => d.metadata.source);
  console.log(`  检索到 ${hits.length} 块: ${JSON.stringify(srcs)}`);
  console.log(`  拼接后 prompt 总长: ${prompt.length} 字符（资料 ${context.length}）`);
  const r = await model.invoke(prompt);
  console.log(`  回答: ${brief(r.content, 600)}`);
}

async function makeRagAgent() {
  const store = await prepareStore();
  const searchKnowledgeBase = tool(
    async ({ query }: { query: string }) => {
      const hits = await store.similaritySearch(query, 3);
      return hits
        .map((h) => `[来源: ${h.metadata.source}]\n${h.pageContent}`)
        .join("\n\n---\n\n");
    },
    {
      name: "search_knowledge_base",
      description: "搜索星云科技公司内部知识库。当用户询问公司制度、流程、IT 服务、报销、产品政策等公司相关问题时必须使用此工具。",
      schema: z.object({ query: z.string().describe("知识库检索查询") }),
    }
  );
  return createAgent({
    model,
    tools: [searchKnowledgeBase],
    systemPrompt:
      "你是星云科技的企业助手。回答公司相关问题时，必须先调用 search_knowledge_base 检索内部知识库，基于资料作答并注明来源；资料中没有的内容如实说明，不要编造。",
  });
}

async function exp3e() {
  const agent = await makeRagAgent();
  const q = "星云科技的 VPN 客户端叫什么？怎么重置密码？";
  console.log(`  问题: ${q}`);
  const r: any = await agent.invoke({ messages: [{ role: "user", content: q }] });
  showChain(r.messages);
}

async function exp3f() {
  const store = await prepareStore();
  const q = "星云科技员工每年有多少天年假？";
  console.log(`  [(a) 无检索] 问: ${q}`);
  const ra = await model.invoke(q);
  console.log(`    -> ${brief(ra.content, 400)}`);
  console.log();
  console.log(`  [(b) 2-step RAG] 问: ${q}`);
  const hits = await store.similaritySearch(q, 3);
  const context = hits.map((d) => `[来源: ${d.metadata.source}]\n${d.pageContent}`).join("\n\n---\n\n");
  const rb = await model.invoke(PROMPT_TEMPLATE.replace("{context}", context).replace("{question}", q));
  const srcs = hits.map((d) => d.metadata.source);
  console.log(`    检索: ${JSON.stringify(srcs)}`);
  console.log(`    -> ${brief(rb.content, 400)}`);
  console.log();
  console.log(`  [(c) Agentic RAG] 问: ${q}`);
  const agent = await makeRagAgent();
  const rc: any = await agent.invoke({ messages: [{ role: "user", content: q }] });
  showChain(rc.messages);
}

async function exp3g() {
  const agent = await makeRagAgent();
  const q =
    "我下周要去北京出差，想顺便提前休 2 天年假：年假申请要提前几个工作日提交？出差住北京一晚最多能报销多少？";
  console.log(`  复合问题: ${q}`);
  const r: any = await agent.invoke({ messages: [{ role: "user", content: q }] });
  showChain(r.messages);
}

// store 对外暴露块数量（getter size，供 exp 2e 使用）

// ============ 主流程 ============
console.log("课 11《Retrieval 检索与 RAG》· 全流程实测（TypeScript 版）");
console.log(`环境: Node ${process.version} | 对话模型 qwen3.8-flash | 嵌入模型 ${SILICONFLOW_MODEL}（4096 维，本地 mock）`);
console.log(`知识库: ${KB_DIR}`);

section("站一 · 1a 无检索直问私有知识");
await exp("1a 无检索直问（两种失败模式）", exp1a);

section("站二 · 知识库构建链路");
await exp("2a 加载：文件 → Document", exp2a);
await exp("2b 切分：三档 chunk_size 对照", exp2b);
await exp("2c 切分：块结构与 metadata", exp2c);
await exp("2d 嵌入：维度 / 批量 / 截维", exp2d);
await exp("2e 入库：add_documents", exp2e);

section("站三 · 检索器与 RAG 架构");
await exp("3a 查询三法", exp3a);
await exp("3b Retriever 三形态", exp3b);
await exp("3c 自定义 retriever + 批量", exp3c);
await exp("3d 2-step RAG 全链路", exp3d);
await exp("3e Agentic RAG（检索做工具）", exp3e);
await exp("3f 三方对照（无检索 / 2-step / agentic）", exp3f);
await exp("3g 跨文档复合问题", exp3g);

console.log("\n全部实验执行完毕。");