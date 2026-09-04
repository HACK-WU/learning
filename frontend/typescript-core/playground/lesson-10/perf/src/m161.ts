export interface M161 { id: string; v: number; tags: string[] }
export function f161(x: M161): string { return x.id + x.v + x.tags.length }
