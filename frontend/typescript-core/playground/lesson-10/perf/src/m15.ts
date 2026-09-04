export interface M15 { id: string; v: number; tags: string[] }
export function f15(x: M15): string { return x.id + x.v + x.tags.length }
