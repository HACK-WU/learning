/**
 * 账本面（account）· 文件版 checkpointer
 *
 * 知识点覆盖：课 10「checkpoint」
 *
 * 为什么必须落盘：挂起期间进程会退出。若 checkpoint 只在内存里，
 * "恢复"就无从谈起——这是"挂起 vs 轮询"权衡的技术前提。
 */
import {
  BaseCheckpointSaver,
  type Checkpoint,
  type CheckpointMetadata,
  type CheckpointTuple,
  type CheckpointListOptions,
} from "@langchain/langgraph-checkpoint";
import fs from "node:fs/promises";
import path from "node:path";

interface SavedFile {
  checkpoint: Checkpoint;
  metadata: CheckpointMetadata;
  pendingWrites?: [string, string, unknown][];
  savedAt: string;
}

export class FileSaver extends BaseCheckpointSaver {
  private dir: string;
  constructor(dir: string) {
    super();
    this.dir = dir;
  }

  private file(threadId: string): string {
    return path.join(this.dir, `${encodeURIComponent(threadId)}.json`);
  }

  private async read(threadId: string): Promise<SavedFile | null> {
    try {
      return JSON.parse(await fs.readFile(this.file(threadId), "utf8")) as SavedFile;
    } catch {
      return null;
    }
  }

  async getTuple(config: any): Promise<CheckpointTuple | undefined> {
    const threadId: string | undefined = config?.configurable?.thread_id;
    if (!threadId) return undefined;
    const saved = await this.read(threadId);
    if (!saved) return undefined;
    return {
      config,
      checkpoint: saved.checkpoint,
      metadata: saved.metadata,
      pendingWrites: saved.pendingWrites,
    };
  }

  async *list(config: any, _opts?: CheckpointListOptions): AsyncGenerator<CheckpointTuple> {
    const t = await this.getTuple(config);
    if (t) yield t;
  }

  async put(config: any, checkpoint: Checkpoint, metadata: CheckpointMetadata): Promise<any> {
    const threadId = config.configurable.thread_id as string;
    const prev = await this.read(threadId);
    await fs.mkdir(this.dir, { recursive: true });
    const payload: SavedFile = {
      checkpoint,
      metadata,
      pendingWrites: prev?.pendingWrites,
      savedAt: new Date().toISOString(),
    };
    await fs.writeFile(this.file(threadId), JSON.stringify(payload, null, 2), "utf8");
    return config;
  }

  async putWrites(config: any, writes: any[], taskId: string): Promise<void> {
    const threadId = config.configurable.thread_id as string;
    const prev = await this.read(threadId);
    const pendingWrites = [
      ...(prev?.pendingWrites ?? []),
      ...writes.map((w) => [taskId, "__pending__", w] as [string, string, unknown]),
    ];
    await fs.mkdir(this.dir, { recursive: true });
    await fs.writeFile(
      this.file(threadId),
      JSON.stringify(
        {
          checkpoint: prev?.checkpoint,
          metadata: prev?.metadata,
          pendingWrites,
          savedAt: new Date().toISOString(),
        },
        null,
        2
      ),
      "utf8"
    );
  }

  /** 线程结束后的清理（BaseCheckpointSaver 要求实现） */
  async deleteThread(threadId: string): Promise<void> {
    await fs.rm(this.file(threadId), { force: true });
  }

  /** 清理线程（供 demo 可重复运行） */
  async clear(threadId: string): Promise<void> {
    await fs.rm(this.file(threadId), { force: true });
  }
}
