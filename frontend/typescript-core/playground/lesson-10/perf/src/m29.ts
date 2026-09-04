export interface M29 { id: string; v: number; tags: string[] }
export function f29(x: M29): string { return x.id + x.v + x.tags.length }
