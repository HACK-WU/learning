export interface M32 { id: string; v: number; tags: string[] }
export function f32(x: M32): string { return x.id + x.v + x.tags.length }
