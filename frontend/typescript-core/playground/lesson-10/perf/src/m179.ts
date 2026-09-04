export interface M179 { id: string; v: number; tags: string[] }
export function f179(x: M179): string { return x.id + x.v + x.tags.length }
