export interface M133 { id: string; v: number; tags: string[] }
export function f133(x: M133): string { return x.id + x.v + x.tags.length }
