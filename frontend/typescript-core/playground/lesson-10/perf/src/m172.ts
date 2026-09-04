export interface M172 { id: string; v: number; tags: string[] }
export function f172(x: M172): string { return x.id + x.v + x.tags.length }
