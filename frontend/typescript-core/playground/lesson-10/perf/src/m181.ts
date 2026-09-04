export interface M181 { id: string; v: number; tags: string[] }
export function f181(x: M181): string { return x.id + x.v + x.tags.length }
