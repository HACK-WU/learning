export interface M82 { id: string; v: number; tags: string[] }
export function f82(x: M82): string { return x.id + x.v + x.tags.length }
