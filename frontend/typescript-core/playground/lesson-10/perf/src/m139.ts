export interface M139 { id: string; v: number; tags: string[] }
export function f139(x: M139): string { return x.id + x.v + x.tags.length }
