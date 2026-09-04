export interface M140 { id: string; v: number; tags: string[] }
export function f140(x: M140): string { return x.id + x.v + x.tags.length }
