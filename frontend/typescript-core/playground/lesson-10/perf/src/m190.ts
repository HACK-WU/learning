export interface M190 { id: string; v: number; tags: string[] }
export function f190(x: M190): string { return x.id + x.v + x.tags.length }
