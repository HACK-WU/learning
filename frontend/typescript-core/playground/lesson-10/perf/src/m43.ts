export interface M43 { id: string; v: number; tags: string[] }
export function f43(x: M43): string { return x.id + x.v + x.tags.length }
