export interface M11 { id: string; v: number; tags: string[] }
export function f11(x: M11): string { return x.id + x.v + x.tags.length }
