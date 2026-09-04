export interface M88 { id: string; v: number; tags: string[] }
export function f88(x: M88): string { return x.id + x.v + x.tags.length }
