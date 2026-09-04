export interface M168 { id: string; v: number; tags: string[] }
export function f168(x: M168): string { return x.id + x.v + x.tags.length }
