// 候选 E：泛型组件式 API，深层属性写错
type Props<T> = {
  data: T[];
  render: (item: T, index: number) => string;
  footer?: { text: string; align: "left" | "right" };
};

declare function List<T>(p: Props<T>): void;

List<string>({
  data: ["a", "b"],
  render: (item) => item.toUpperCase(),
  footer: { text: "total: 2", align: "center" },
});
