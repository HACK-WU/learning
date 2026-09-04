export interface M31 { id: string; v: number; tags: string[] }
export function f31(x: M31): string { return x.id + x.v + x.tags.length }
