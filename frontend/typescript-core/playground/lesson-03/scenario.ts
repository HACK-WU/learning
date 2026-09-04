// 课 3 · 第四幕：给「统一记录格式」上类型

// 统一记录格式：CSV 和 API 两边的数据都要能进这个模子
interface DataRow {
  id: string;
  name: string;
  score: number;
}

// 来源一：CSV 解析
function fromCsv(line: string): DataRow {
  const [id, name, rawScore] = line.split(",");
  return { id, name, score: Number(rawScore) };
}

// 来源二：API，多带了一个字段
interface ApiRow {
  id: string;
  name: string;
  score: number;
  source: string;
}

function report(rows: readonly DataRow[]): void {
  for (const row of rows) {
    console.log(`${row.id} ${row.name}: ${row.score}`);
  }
}

const csvRows: DataRow[] = ["u1,Alice,98", "u2,Bob,76"].map(fromCsv);
const apiRows: ApiRow[] = [{ id: "u3", name: "Cindy", score: 89, source: "api" }];

// 两个来源混在一起：ApiRow 结构上兼容 DataRow，不需要任何转换
const all: DataRow[] = [...csvRows, ...apiRows];
report(all);

// 配置用 satisfies：既检查合规性，又保留"我选的是 score"这个信息
type ReportConfig = { title: string; sortBy: "id" | "score" };
const config = { title: "Score Report", sortBy: "score" } satisfies ReportConfig;
const sortKey: "score" = config.sortBy; // ✅ satisfies 保留了字面量

console.log(`${config.title} - sorted by ${sortKey}`);
