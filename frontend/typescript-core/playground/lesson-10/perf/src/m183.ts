export interface M183 { id: string; v: number; tags: string[] }
export function f183(x: M183): string { return x.id + x.v + x.tags.length }
