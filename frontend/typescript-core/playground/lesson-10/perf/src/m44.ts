export interface M44 { id: string; v: number; tags: string[] }
export function f44(x: M44): string { return x.id + x.v + x.tags.length }
