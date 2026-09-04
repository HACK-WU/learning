// 候选 G：同一处同时错好几个（缺属性 + 类型错 + 多余属性）
interface Payload {
  id: string;
  amount: number;
  tags: string[];
  meta: { source: string; retries: number };
}

declare function send(p: Payload): void;

send({
  id: 1,
  amount: "100",
  tags: [1, 2],
  meta: { source: "api", retries: 0 },
  extra: true,
});
