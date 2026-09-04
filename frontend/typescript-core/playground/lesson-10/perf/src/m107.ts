export interface M107 { id: string; v: number; tags: string[] }
export function f107(x: M107): string { return x.id + x.v + x.tags.length }
