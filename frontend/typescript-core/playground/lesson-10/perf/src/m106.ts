export interface M106 { id: string; v: number; tags: string[] }
export function f106(x: M106): string { return x.id + x.v + x.tags.length }
