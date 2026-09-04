export interface M66 { id: string; v: number; tags: string[] }
export function f66(x: M66): string { return x.id + x.v + x.tags.length }
