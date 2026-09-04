export interface M25 { id: string; v: number; tags: string[] }
export function f25(x: M25): string { return x.id + x.v + x.tags.length }
