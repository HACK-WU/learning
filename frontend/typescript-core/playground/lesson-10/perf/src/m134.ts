export interface M134 { id: string; v: number; tags: string[] }
export function f134(x: M134): string { return x.id + x.v + x.tags.length }
