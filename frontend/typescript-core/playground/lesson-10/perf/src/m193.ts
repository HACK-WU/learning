export interface M193 { id: string; v: number; tags: string[] }
export function f193(x: M193): string { return x.id + x.v + x.tags.length }
