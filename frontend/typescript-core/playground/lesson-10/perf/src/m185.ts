export interface M185 { id: string; v: number; tags: string[] }
export function f185(x: M185): string { return x.id + x.v + x.tags.length }
