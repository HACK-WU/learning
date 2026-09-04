export interface M77 { id: string; v: number; tags: string[] }
export function f77(x: M77): string { return x.id + x.v + x.tags.length }
