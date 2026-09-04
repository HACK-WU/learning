export interface M20 { id: string; v: number; tags: string[] }
export function f20(x: M20): string { return x.id + x.v + x.tags.length }
