export interface M122 { id: string; v: number; tags: string[] }
export function f122(x: M122): string { return x.id + x.v + x.tags.length }
