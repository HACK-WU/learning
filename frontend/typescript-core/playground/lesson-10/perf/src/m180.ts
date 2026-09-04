export interface M180 { id: string; v: number; tags: string[] }
export function f180(x: M180): string { return x.id + x.v + x.tags.length }
