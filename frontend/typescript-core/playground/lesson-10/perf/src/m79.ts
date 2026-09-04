export interface M79 { id: string; v: number; tags: string[] }
export function f79(x: M79): string { return x.id + x.v + x.tags.length }
