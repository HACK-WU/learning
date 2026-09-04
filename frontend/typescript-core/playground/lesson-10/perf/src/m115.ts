export interface M115 { id: string; v: number; tags: string[] }
export function f115(x: M115): string { return x.id + x.v + x.tags.length }
