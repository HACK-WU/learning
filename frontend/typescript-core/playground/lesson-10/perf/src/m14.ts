export interface M14 { id: string; v: number; tags: string[] }
export function f14(x: M14): string { return x.id + x.v + x.tags.length }
