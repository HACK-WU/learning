// 候选 A：判别式联合，少传一个属性
type UiEvent =
  | { type: "click"; x: number; y: number }
  | { type: "keydown"; key: string; ctrl: boolean }
  | { type: "scroll"; delta: number };

declare function handle(e: UiEvent): void;

handle({ type: "click", x: 1 });
