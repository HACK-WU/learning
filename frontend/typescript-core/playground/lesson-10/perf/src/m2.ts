export interface M2 { id: string; v: number; tags: string[] }
export function f2(x: M2): string { return x.id + x.v + x.tags.length }
