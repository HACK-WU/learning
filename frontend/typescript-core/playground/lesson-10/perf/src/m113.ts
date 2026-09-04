export interface M113 { id: string; v: number; tags: string[] }
export function f113(x: M113): string { return x.id + x.v + x.tags.length }
