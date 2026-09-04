export interface M73 { id: string; v: number; tags: string[] }
export function f73(x: M73): string { return x.id + x.v + x.tags.length }
