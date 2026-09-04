export interface M62 { id: string; v: number; tags: string[] }
export function f62(x: M62): string { return x.id + x.v + x.tags.length }
