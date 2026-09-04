export interface M51 { id: string; v: number; tags: string[] }
export function f51(x: M51): string { return x.id + x.v + x.tags.length }
