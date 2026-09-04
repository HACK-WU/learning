export interface M83 { id: string; v: number; tags: string[] }
export function f83(x: M83): string { return x.id + x.v + x.tags.length }
