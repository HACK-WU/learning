export interface M101 { id: string; v: number; tags: string[] }
export function f101(x: M101): string { return x.id + x.v + x.tags.length }
