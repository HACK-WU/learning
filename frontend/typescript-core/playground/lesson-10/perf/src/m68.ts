export interface M68 { id: string; v: number; tags: string[] }
export function f68(x: M68): string { return x.id + x.v + x.tags.length }
