export interface M109 { id: string; v: number; tags: string[] }
export function f109(x: M109): string { return x.id + x.v + x.tags.length }
