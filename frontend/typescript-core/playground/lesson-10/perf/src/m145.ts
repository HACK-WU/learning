export interface M145 { id: string; v: number; tags: string[] }
export function f145(x: M145): string { return x.id + x.v + x.tags.length }
