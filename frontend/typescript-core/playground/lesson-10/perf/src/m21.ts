export interface M21 { id: string; v: number; tags: string[] }
export function f21(x: M21): string { return x.id + x.v + x.tags.length }
