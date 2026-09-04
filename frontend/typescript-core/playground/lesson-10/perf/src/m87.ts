export interface M87 { id: string; v: number; tags: string[] }
export function f87(x: M87): string { return x.id + x.v + x.tags.length }
