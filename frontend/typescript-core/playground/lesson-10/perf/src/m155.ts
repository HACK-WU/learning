export interface M155 { id: string; v: number; tags: string[] }
export function f155(x: M155): string { return x.id + x.v + x.tags.length }
