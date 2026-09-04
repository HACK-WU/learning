export interface M50 { id: string; v: number; tags: string[] }
export function f50(x: M50): string { return x.id + x.v + x.tags.length }
