export interface M165 { id: string; v: number; tags: string[] }
export function f165(x: M165): string { return x.id + x.v + x.tags.length }
