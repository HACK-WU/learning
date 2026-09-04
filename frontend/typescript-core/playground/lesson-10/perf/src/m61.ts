export interface M61 { id: string; v: number; tags: string[] }
export function f61(x: M61): string { return x.id + x.v + x.tags.length }
