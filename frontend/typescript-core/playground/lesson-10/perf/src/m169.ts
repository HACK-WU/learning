export interface M169 { id: string; v: number; tags: string[] }
export function f169(x: M169): string { return x.id + x.v + x.tags.length }
