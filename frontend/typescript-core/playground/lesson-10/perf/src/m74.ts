export interface M74 { id: string; v: number; tags: string[] }
export function f74(x: M74): string { return x.id + x.v + x.tags.length }
