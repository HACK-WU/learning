export interface M70 { id: string; v: number; tags: string[] }
export function f70(x: M70): string { return x.id + x.v + x.tags.length }
