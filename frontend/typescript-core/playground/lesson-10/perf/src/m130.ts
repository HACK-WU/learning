export interface M130 { id: string; v: number; tags: string[] }
export function f130(x: M130): string { return x.id + x.v + x.tags.length }
