// 生成两个「体量相同、但类型负担不同」的项目，用于对比编译耗时。
//   simple/ —— 结果直接写成字面量（不计算）
//   gym/    —— 同样的结果，由递归条件类型算出来（Split + Join 往返 + RouteParams）
// 两边都强制对结果做赋值检查，避免 TS 的惰性求值让测量失真。
//
// ⚠️ 第一版（100 文件 × 20 条短路由）实测 simple=154ms / gym=140ms —— 全是噪音，
//    因为 node 启动开销就占了 100ms+。本版把工作量加大到 200 文件 × 20 条长路由，
//    并让每条都跑 Split → Join 往返（强制完整求值），才测得出差异。
const { writeFileSync, mkdirSync, rmSync } = require("node:fs");
const path = require("node:path");

const ROOT = __dirname;
const N_FILES = 200;

// 20 条长路由，每条都能算出不同的参数联合
const RAW = [
  ["/api/v2/organizations/:orgId/workspaces/:workspaceId/projects/:projectId", ["orgId", "workspaceId", "projectId"]],
  ["/api/v2/organizations/:orgId/workspaces/:workspaceId/members/:memberId", ["orgId", "workspaceId", "memberId"]],
  ["/api/v2/projects/:projectId/pipelines/:pipelineId/runs/:runId", ["projectId", "pipelineId", "runId"]],
  ["/api/v2/projects/:projectId/pipelines/:pipelineId/runs/:runId/steps/:stepId", ["projectId", "pipelineId", "runId", "stepId"]],
  ["/api/v2/projects/:projectId/artifacts/:artifactId/versions/:versionId", ["projectId", "artifactId", "versionId"]],
  ["/api/v2/registries/:registryId/images/:imageId/tags/:tagId", ["registryId", "imageId", "tagId"]],
  ["/api/v2/secrets/:secretId/revisions/:revisionId", ["secretId", "revisionId"]],
  ["/api/v2/webhooks/:webhookId/deliveries/:deliveryId", ["webhookId", "deliveryId"]],
  ["/api/v2/audit/actors/:actorId/events/:eventId", ["actorId", "eventId"]],
  ["/api/v2/billing/accounts/:accountId/invoices/:invoiceId", ["accountId", "invoiceId"]],
  ["/api/v2/billing/accounts/:accountId/subscriptions/:subscriptionId", ["accountId", "subscriptionId"]],
  ["/api/v2/teams/:teamId/projects/:projectId/environments/:envId", ["teamId", "projectId", "envId"]],
  ["/api/v2/teams/:teamId/projects/:projectId/environments/:envId/deploys/:deployId", ["teamId", "projectId", "envId", "deployId"]],
  ["/api/v2/datasets/:datasetId/schemas/:schemaId/fields/:fieldId", ["datasetId", "schemaId", "fieldId"]],
  ["/api/v2/datasets/:datasetId/records/:recordId", ["datasetId", "recordId"]],
  ["/api/v2/notebooks/:notebookId/cells/:cellId/outputs/:outputId", ["notebookId", "cellId", "outputId"]],
  ["/api/v2/schedules/:scheduleId/triggers/:triggerId", ["scheduleId", "triggerId"]],
  ["/api/v2/queues/:queueId/messages/:messageId", ["queueId", "messageId"]],
  ["/api/v2/topics/:topicId/subscriptions/:subscriptionId/consumers/:consumerId", ["topicId", "subscriptionId", "consumerId"]],
  ["/api/v2/clusters/:clusterId/nodes/:nodeId/pods/:podId", ["clusterId", "nodeId", "podId"]],
];

const TYPES = `// 递归条件类型三件套：拆分 / 连接 / 路由参数提取（全部尾递归写法）
export type Split<S extends string, Sep extends string> = SplitHelper<S, Sep, []>;
type SplitHelper<S extends string, Sep extends string, Acc extends string[]> =
  S extends \`\${infer Head}\${Sep}\${infer Tail}\`
    ? SplitHelper<Tail, Sep, [...Acc, Head]>
    : [...Acc, S];

// ⚠️ 注意这里用的是 First 标志位，而不是 \`Acc extends ""\`。
//    用 Acc 判断是否首元素是个经典 bug：当第一个元素本身就是 "" 时（比如
//    Split<"/a/b", "/"> 得到 ["", "a", "b"]），它会被整个吞掉，
//    Join 出来的结果是 "a/b" 而不是 "/a/b"。详见 playground 里的 join-bug.ts。
export type Join<T extends readonly string[], Sep extends string> = JoinHelper<T, Sep, "", true>;
type JoinHelper<
  T extends readonly string[],
  Sep extends string,
  Acc extends string,
  First extends boolean,
> = T extends [infer Head extends string, ...infer Rest extends readonly string[]]
  ? JoinHelper<Rest, Sep, First extends true ? Head : \`\${Acc}\${Sep}\${Head}\`, false>
  : Acc;

export type RouteParams<S extends string> = RouteParamsHelper<S, never>;
type RouteParamsHelper<S extends string, Acc> =
  S extends \`\${string}:\${infer Param}/\${infer Rest}\`
    ? RouteParamsHelper<Rest, Acc | Param>
    : S extends \`\${string}:\${infer Param}\`
      ? Acc | Param
      : Acc;
`;

// 把 "/a/:b/c" 拆成 ["", "a", ":b", "c"]，作为 simple 版要手写的期望结果
function splitLiteral(route) {
  return "[" + route.split("/").map((s) => JSON.stringify(s)).join(", ") + "]";
}

function buildFile(kind) {
  const lines = [];
  if (kind === "gym") {
    lines.push(`import type { Split, Join, RouteParams } from "./types.js";`);
    lines.push("");
  }
  RAW.forEach(([route], j) => {
    if (kind === "gym") {
      lines.push(`type P${j} = RouteParams<"${route}">;`);
      lines.push(`type S${j} = Split<"${route}", "/">;`);
      lines.push(`type J${j} = Join<S${j}, "/">;`);
    } else {
      lines.push(`type S${j} = ${splitLiteral(route)};`);
      lines.push(`type J${j} = "${route}";`);
    }
  });
  lines.push("");
  RAW.forEach(([route, params], j) => {
    const paramsUnion = params.map((p) => JSON.stringify(p)).join(" | ");
    if (kind === "gym") lines.push(`declare const p${j}: P${j};`);
    lines.push(`declare const s${j}: S${j};`);
    lines.push(`declare const j${j}: J${j};`);
    if (kind === "gym") lines.push(`export const op${j}: ${paramsUnion} = p${j};`);
    lines.push(`export const os${j}: ${splitLiteral(route)} = s${j};`);
    lines.push(`export const oj${j}: "${route}" = j${j};`);  // 往返相等 → 强制 Split 与 Join 都被完整求值
  });
  return lines.join("\n") + "\n";
}

for (const kind of ["simple", "gym"]) {
  const dir = path.join(ROOT, kind);
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(dir, { recursive: true });
  if (kind === "gym") writeFileSync(path.join(dir, "types.ts"), TYPES);
  for (let i = 0; i < N_FILES; i++) {
    writeFileSync(path.join(dir, `f${i}.ts`), buildFile(kind));
  }
  writeFileSync(
    path.join(dir, "tsconfig.json"),
    JSON.stringify(
      {
        compilerOptions: {
          target: "esnext",
          module: "nodenext",
          moduleResolution: "nodenext",
          strict: true,
          types: [],
          lib: ["esnext"],
          skipLibCheck: true,
          noEmit: true,
        },
        include: ["./*.ts"],
      },
      null,
      2,
    ),
  );
  writeFileSync(path.join(dir, "package.json"), JSON.stringify({ type: "module" }, null, 2));
}

console.log(`generated ${N_FILES} files x 2 projects (simple / gym)`);
