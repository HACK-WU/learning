export interface M120 { id: string; v: number; tags: string[] }
export function f120(x: M120): string { return x.id + x.v + x.tags.length }
