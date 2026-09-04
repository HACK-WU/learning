export interface M182 { id: string; v: number; tags: string[] }
export function f182(x: M182): string { return x.id + x.v + x.tags.length }
