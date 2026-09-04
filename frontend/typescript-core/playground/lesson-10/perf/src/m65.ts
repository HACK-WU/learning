export interface M65 { id: string; v: number; tags: string[] }
export function f65(x: M65): string { return x.id + x.v + x.tags.length }
