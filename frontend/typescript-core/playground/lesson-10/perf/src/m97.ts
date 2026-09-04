export interface M97 { id: string; v: number; tags: string[] }
export function f97(x: M97): string { return x.id + x.v + x.tags.length }
