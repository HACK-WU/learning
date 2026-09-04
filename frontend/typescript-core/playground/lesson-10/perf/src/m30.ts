export interface M30 { id: string; v: number; tags: string[] }
export function f30(x: M30): string { return x.id + x.v + x.tags.length }
