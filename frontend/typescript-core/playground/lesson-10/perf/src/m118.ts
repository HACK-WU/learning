export interface M118 { id: string; v: number; tags: string[] }
export function f118(x: M118): string { return x.id + x.v + x.tags.length }
