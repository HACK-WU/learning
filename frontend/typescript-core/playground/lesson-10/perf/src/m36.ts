export interface M36 { id: string; v: number; tags: string[] }
export function f36(x: M36): string { return x.id + x.v + x.tags.length }
