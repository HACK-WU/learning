export interface M192 { id: string; v: number; tags: string[] }
export function f192(x: M192): string { return x.id + x.v + x.tags.length }
