export interface M24 { id: string; v: number; tags: string[] }
export function f24(x: M24): string { return x.id + x.v + x.tags.length }
