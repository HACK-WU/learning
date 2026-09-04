export interface M126 { id: string; v: number; tags: string[] }
export function f126(x: M126): string { return x.id + x.v + x.tags.length }
