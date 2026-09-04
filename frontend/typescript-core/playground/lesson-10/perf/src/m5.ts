export interface M5 { id: string; v: number; tags: string[] }
export function f5(x: M5): string { return x.id + x.v + x.tags.length }
