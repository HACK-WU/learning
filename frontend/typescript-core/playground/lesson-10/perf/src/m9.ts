export interface M9 { id: string; v: number; tags: string[] }
export function f9(x: M9): string { return x.id + x.v + x.tags.length }
