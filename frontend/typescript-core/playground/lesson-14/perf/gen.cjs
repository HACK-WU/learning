// 生成一个「Check 阶段吃重」的项目：既有类型计算，又有大量可赋值性检查。
// 用法：node gen.js [文件数] [每文件记录数]
const { writeFileSync, mkdirSync, rmSync } = require("node:fs");
const path = require("node:path");

const ROOT = __dirname;
const N_FILES = Number(process.argv[2] ?? 300);
const N_RECS = Number(process.argv[3] ?? 30);

// 一段既有条件类型又有映射类型的「类型计算」
const TYPES = `
// 递归条件类型：从路径里提取参数名（尾递归）
export type RouteParams<S extends string> = RouteParamsHelper<S, never>;
type RouteParamsHelper<S extends string, Acc> =
  S extends \`\${string}:\${infer P}/\${infer R}\`
    ? RouteParamsHelper<R, Acc | P>
    : S extends \`\${string}:\${infer P}\`
      ? Acc | P
      : Acc;

// 映射类型 + 条件类型：把形状包一层
export type Wrapped<T> = { [K in keyof T]: T[K] extends string ? \`str:\${T[K]}\` : T[K] };

// 深层可空类型
export type DeepPartial<T> = { [K in keyof T]?: T[K] extends object ? DeepPartial<T[K]> : T[K] };
`;

// 20 条路由，用于 RouteParams 计算
const ROUTES = [
  ["/orgs/:orgId/workspaces/:workspaceId/projects/:projectId", ['"orgId"', '"workspaceId"', '"projectId"']],
  ["/orgs/:orgId/members/:memberId", ['"orgId"', '"memberId"']],
  ["/projects/:projectId/runs/:runId/steps/:stepId", ['"projectId"', '"runId"', '"stepId"']],
  ["/registries/:registryId/images/:imageId", ['"registryId"', '"imageId"']],
  ["/queues/:queueId/messages/:messageId", ['"queueId"', '"messageId"']],
  ["/clusters/:clusterId/nodes/:nodeId", ['"clusterId"', '"nodeId"']],
  ["/datasets/:datasetId/records/:recordId", ['"datasetId"', '"recordId"']],
  ["/topics/:topicId/consumers/:consumerId", ['"topicId"', '"consumerId"']],
  ["/schedules/:scheduleId/triggers/:triggerId", ['"scheduleId"', '"triggerId"']],
  ["/secrets/:secretId/revisions/:revisionId", ['"secretId"', '"revisionId"']],
  ["/billing/:accountId/invoices/:invoiceId", ['"accountId"', '"invoiceId"']],
  ["/audit/:actorId/events/:eventId", ['"actorId"', '"eventId"']],
  ["/webhooks/:webhookId/deliveries/:deliveryId", ['"webhookId"', '"deliveryId"']],
  ["/notebooks/:notebookId/cells/:cellId", ['"notebookId"', '"cellId"']],
  ["/artifacts/:artifactId/versions/:versionId", ['"artifactId"', '"versionId"']],
  ["/teams/:teamId/environments/:envId", ['"teamId"', '"envId"']],
  ["/pipelines/:pipelineId/stages/:stageId", ['"pipelineId"', '"stageId"']],
  ["/apikeys/:keyId/scopes/:scopeId", ['"keyId"', '"scopeId"']],
  ["/alerts/:alertId/history/:historyId", ['"alertId"', '"historyId"']],
  ["/exports/:exportId/chunks/:chunkId", ['"exportId"', '"chunkId"']],
];

function buildFile(i) {
  const lines = [`import type { RouteParams, Wrapped, DeepPartial } from "./types.js";`, ""];
  // ① 类型计算：每条路由算一次参数联合
  ROUTES.forEach(([route, params], j) => {
    lines.push(`export type P${i}_${j} = RouteParams<"${route}">;`);
    lines.push(`declare const p${j}: P${i}_${j};`);
    lines.push(`export const op${j}: ${params.join(" | ")} = p${j};`);
  });
  lines.push("");
  // ② 大量可赋值性检查：嵌套对象字面量
  for (let k = 0; k < N_RECS; k++) {
    lines.push(`interface Rec${i}_${k} {`);
    lines.push(`  id: string;`);
    lines.push(`  amount: number;`);
    lines.push(`  tags: string[];`);
    lines.push(`  nested: { flag: boolean; label: string; deep: { z: number } };`);
    lines.push(`  wrapped: Wrapped<{ a: string; b: number }>;`);
    lines.push(`  partial?: DeepPartial<{ x: string; y: { m: number } }>;`);
    lines.push(`}`);
    lines.push(
      `export const rec${k}: Rec${i}_${k} = { id: "r${k}", amount: ${k}, tags: ["t${k}"], nested: { flag: true, label: "l${k}", deep: { z: ${k} } }, wrapped: { a: \`str:v${k}\`, b: ${k} }, partial: { x: "x", y: { m: ${k} } } };`,
    );
    lines.push("");
  }
  return lines.join("\n");
}

const dir = path.join(ROOT, "src");
rmSync(dir, { recursive: true, force: true });
mkdirSync(dir, { recursive: true });
writeFileSync(path.join(dir, "types.ts"), TYPES);
for (let i = 0; i < N_FILES; i++) {
  writeFileSync(path.join(dir, `f${i}.ts`), buildFile(i));
}
writeFileSync(
  path.join(ROOT, "tsconfig.json"),
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
      include: ["./src"],
    },
    null,
    2,
  ),
);
writeFileSync(path.join(ROOT, "package.json"), JSON.stringify({ type: "module" }, null, 2));

console.log(`generated ${N_FILES} files x (${ROUTES.length} route types + ${N_RECS} records)`);
