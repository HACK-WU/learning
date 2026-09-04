export interface M85 { id: string; v: number; tags: string[] }
export function f85(x: M85): string { return x.id + x.v + x.tags.length }
