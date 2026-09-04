export interface M80 { id: string; v: number; tags: string[] }
export function f80(x: M80): string { return x.id + x.v + x.tags.length }
