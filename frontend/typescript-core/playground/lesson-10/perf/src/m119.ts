export interface M119 { id: string; v: number; tags: string[] }
export function f119(x: M119): string { return x.id + x.v + x.tags.length }
