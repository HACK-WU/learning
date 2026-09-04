export interface M19 { id: string; v: number; tags: string[] }
export function f19(x: M19): string { return x.id + x.v + x.tags.length }
