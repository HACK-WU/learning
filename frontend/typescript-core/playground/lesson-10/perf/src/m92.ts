export interface M92 { id: string; v: number; tags: string[] }
export function f92(x: M92): string { return x.id + x.v + x.tags.length }
