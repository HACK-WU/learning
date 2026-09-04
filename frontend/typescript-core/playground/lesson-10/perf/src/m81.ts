export interface M81 { id: string; v: number; tags: string[] }
export function f81(x: M81): string { return x.id + x.v + x.tags.length }
