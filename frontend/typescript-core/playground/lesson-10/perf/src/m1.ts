export interface M1 { id: string; v: number; tags: string[] }
export function f1(x: M1): string { return x.id + x.v + x.tags.length }
