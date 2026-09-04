export interface M16 { id: string; v: number; tags: string[] }
export function f16(x: M16): string { return x.id + x.v + x.tags.length }
