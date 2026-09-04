export interface M8 { id: string; v: number; tags: string[] }
export function f8(x: M8): string { return x.id + x.v + x.tags.length }
