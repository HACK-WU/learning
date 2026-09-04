export interface M17 { id: string; v: number; tags: string[] }
export function f17(x: M17): string { return x.id + x.v + x.tags.length }
