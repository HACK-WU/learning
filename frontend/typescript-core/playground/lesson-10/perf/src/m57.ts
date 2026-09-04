export interface M57 { id: string; v: number; tags: string[] }
export function f57(x: M57): string { return x.id + x.v + x.tags.length }
