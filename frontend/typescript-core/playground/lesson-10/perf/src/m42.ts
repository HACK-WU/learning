export interface M42 { id: string; v: number; tags: string[] }
export function f42(x: M42): string { return x.id + x.v + x.tags.length }
