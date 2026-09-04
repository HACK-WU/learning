export interface M103 { id: string; v: number; tags: string[] }
export function f103(x: M103): string { return x.id + x.v + x.tags.length }
