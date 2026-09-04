export interface M26 { id: string; v: number; tags: string[] }
export function f26(x: M26): string { return x.id + x.v + x.tags.length }
