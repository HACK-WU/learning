export interface M39 { id: string; v: number; tags: string[] }
export function f39(x: M39): string { return x.id + x.v + x.tags.length }
