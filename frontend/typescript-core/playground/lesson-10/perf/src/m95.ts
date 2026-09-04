export interface M95 { id: string; v: number; tags: string[] }
export function f95(x: M95): string { return x.id + x.v + x.tags.length }
