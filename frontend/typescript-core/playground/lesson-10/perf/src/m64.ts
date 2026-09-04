export interface M64 { id: string; v: number; tags: string[] }
export function f64(x: M64): string { return x.id + x.v + x.tags.length }
