/**
 * 执行面（execute）· 工具来源统一抽象
 *
 * 知识点覆盖：课 8「工具从哪来」「授权与暴露分离」
 *
 * 设计要点：工具分两层——provider 负责"有哪些工具"（声明），
 * 执行器负责"怎么跑"（实现）。权限校验挂在执行器的入口，而不是
 * 每个工具内部，这样任何调用路径（含直接调用）都过同一道闸。
 */
import type { AgentDefinition } from "../definition/agent-definition.js";

export type SqlOp = "read" | "write";

export interface ToolSpec {
  name: string;
  description: string;
  op: SqlOp;
  /** 参数校验：入口即拦，避免脏参数进入执行器 */
  parse(input: unknown): Record<string, unknown>;
}

export interface ToolResult {
  ok: boolean;
  output: string;
}

/** 一个极简的内存"数据库"，让示例可运行且不依赖外部服务 */
export class FakeDatabase {
  private tables = new Map<string, string[]>([
    ["orders", ["id", "amount", "status"]],
    ["users", ["id", "email"]],
  ]);
  private log: string[] = [];

  query(sql: string): string {
    const t = /from\s+(\w+)/i.exec(sql)?.[1];
    if (!t || !this.tables.has(t)) return `[query] 表不存在：${t ?? "(未指定)"}`;
    this.log.push(`Q ${sql}`);
    return `[query] ${t} 列：${this.tables.get(t)!.join(", ")}`;
  }

  execute(sql: string): string {
    const m = /alter\s+table\s+(\w+)\s+add\s+column\s+(\w+)/i.exec(sql);
    if (!m) return `[execute] 不支持的语句（本示例只演示 ADD COLUMN）`;
    const [, table, col] = m;
    if (!this.tables.has(table)) return `[execute] 表不存在：${table}`;
    const cols = this.tables.get(table)!;
    if (cols.includes(col)) return `[execute] 列已存在：${table}.${col}`;
    cols.push(col);
    this.log.push(`W ${sql}`);
    return `[execute] 已为 ${table} 添加列 ${col}`;
  }

  /** 账本：谁在什么时候改了什么（供验收与排障） */
  history(): string[] {
    return [...this.log];
  }
  schemaOf(table: string): string[] {
    return [...(this.tables.get(table) ?? [])];
  }
}

/**
 * provider：只声明"有哪些工具"，不持有执行逻辑。
 *
 * 为什么要分开：暴露（给模型看什么）与授权（能不能执行）是两件事。
 * 若工具自己实现权限判断，任何绕过工具的调用都能逃过校验。
 */
export class ToolProvider {
  private specs: ToolSpec[];

  constructor(specs: ToolSpec[]) {
    this.specs = specs;
  }

  /** 静态清单：给界面与配置校验用，无副作用 */
  listNames(): string[] {
    return this.specs.map((s) => s.name);
  }

  /** 按定义过滤出"这次真正暴露给模型"的工具 */
  forDefinition(def: AgentDefinition): ToolSpec[] {
    const allowed = new Set(def.tools);
    return this.specs.filter((s) => allowed.has(s.name));
  }

  get(name: string): ToolSpec | undefined {
    return this.specs.find((s) => s.name === name);
  }

  static builtin(db: FakeDatabase): ToolProvider {
    return new ToolProvider([
      {
        name: "querySql",
        description: "执行只读查询，返回表结构或行数",
        op: "read",
        parse(input) {
          const sql = String((input as any)?.sql ?? "");
          if (!/^\s*select\b/i.test(sql)) throw new Error("querySql 只接受 SELECT");
          return { sql };
        },
      },
      {
        name: "executeSql",
        description: "执行变更语句（DDL/DML），需人工审批",
        op: "write",
        parse(input) {
          const sql = String((input as any)?.sql ?? "");
          if (/^\s*(drop|truncate)\b/i.test(sql)) {
            throw new Error("本示例禁止 DROP / TRUNCATE（演示工具边界）");
          }
          if (!/^\s*(alter|insert|update)\b/i.test(sql)) {
            throw new Error("executeSql 只接受 ALTER / INSERT / UPDATE");
          }
          return { sql };
        },
      },
    ]);
  }

  /** 模拟第二个来源（远端工具源），证明"多源统一"不是只写一种 */
  static remote(): ToolProvider {
    return new ToolProvider([
      {
        name: "notifyOwner",
        description: "变更完成后通知表负责人（模拟远端服务）",
        op: "read",
        parse(input) {
          return { table: String((input as any)?.table ?? "") };
        },
      },
    ]);
  }
}

/** 合并多个来源：同名工具以后者覆盖（真实系统应报错，这里演示策略） */
export function mergeProviders(...providers: ToolProvider[]): ToolProvider {
  const map = new Map<string, ToolSpec>();
  for (const p of providers) {
    for (const name of p.listNames()) {
      const spec = p.get(name);
      if (spec) map.set(name, spec);
    }
  }
  return new ToolProvider([...map.values()]);
}
