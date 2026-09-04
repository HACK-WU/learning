export interface M40 { id: string; v: number; tags: string[] }
export function f40(x: M40): string { return x.id + x.v + x.tags.length }
