// 课 3 · 知识点 1：对象类型 —— interface 与 type

// ① interface：描述"对象长什么样"
interface DataRow {
  id: string;
  name: string;
  score: number;
  source?: string; // 可选属性：可以有，也可以没有
  readonly createdAt: string; // 只读属性：赋值后不能再改
}

// ② type：类型别名，同样能描述对象
type DataRowAlias = {
  id: string;
  name: string;
  score: number;
  source?: string;
  readonly createdAt: string;
};

// ③ interface 用 extends 扩展
interface ApiRow extends DataRow {
  endpoint: string;
}

// ④ type 用交叉类型 & 扩展
type ApiRowAlias = DataRowAlias & { endpoint: string };

// ⑤ 索引签名：键名不确定，但值的类型确定
interface ScoreMap {
  [userId: string]: number;
}
const scores: ScoreMap = { u1: 98, u2: 76 };
scores.u3 = 89; // 键名任意，值必须是 number

// ⑥ interface 支持声明合并：同名自动合并
interface AppConfig {
  mode: string;
}
interface AppConfig {
  port: number;
}
const cfg: AppConfig = { mode: "dev", port: 3000 }; // 两个声明合并后，两个属性都必需

const row: DataRow = { id: "u1", name: "Alice", score: 98, createdAt: "2026-09-01" };
const apiRow: ApiRow = {
  id: "u2",
  name: "Bob",
  score: 76,
  createdAt: "2026-09-02",
  endpoint: "/users",
};

console.log(row, apiRow, scores, cfg);
