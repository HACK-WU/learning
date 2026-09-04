export interface M58 { id: string; v: number; tags: string[] }
export function f58(x: M58): string { return x.id + x.v + x.tags.length }
