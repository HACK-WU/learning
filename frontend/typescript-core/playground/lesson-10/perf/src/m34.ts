export interface M34 { id: string; v: number; tags: string[] }
export function f34(x: M34): string { return x.id + x.v + x.tags.length }
