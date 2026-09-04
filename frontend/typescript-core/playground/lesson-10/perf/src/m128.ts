export interface M128 { id: string; v: number; tags: string[] }
export function f128(x: M128): string { return x.id + x.v + x.tags.length }
