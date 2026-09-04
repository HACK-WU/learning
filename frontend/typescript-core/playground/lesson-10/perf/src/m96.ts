export interface M96 { id: string; v: number; tags: string[] }
export function f96(x: M96): string { return x.id + x.v + x.tags.length }
