export interface M71 { id: string; v: number; tags: string[] }
export function f71(x: M71): string { return x.id + x.v + x.tags.length }
