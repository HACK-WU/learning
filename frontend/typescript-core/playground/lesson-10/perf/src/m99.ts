export interface M99 { id: string; v: number; tags: string[] }
export function f99(x: M99): string { return x.id + x.v + x.tags.length }
