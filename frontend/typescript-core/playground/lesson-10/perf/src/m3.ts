export interface M3 { id: string; v: number; tags: string[] }
export function f3(x: M3): string { return x.id + x.v + x.tags.length }
