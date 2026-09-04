// 候选 H：泛型 + 映射类型，最内层写错
type Form<T> = {
  [K in keyof T]: {
    value: T[K];
    error: string | null;
    opts: { required: boolean; label: string };
  };
};

declare function render<T extends Record<string, unknown>>(form: Form<T>): void;

render({
  name: { value: "amy", error: null, opts: { required: true, label: "Name" } },
  age: { value: 18, error: null, opts: { required: 1, label: "Age" } },
});
