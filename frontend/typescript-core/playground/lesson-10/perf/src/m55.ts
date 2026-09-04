export interface M55 { id: string; v: number; tags: string[] }
export function f55(x: M55): string { return x.id + x.v + x.tags.length }
