export interface M6 { id: string; v: number; tags: string[] }
export function f6(x: M6): string { return x.id + x.v + x.tags.length }
