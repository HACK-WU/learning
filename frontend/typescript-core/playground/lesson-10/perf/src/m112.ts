export interface M112 { id: string; v: number; tags: string[] }
export function f112(x: M112): string { return x.id + x.v + x.tags.length }
