export interface M90 { id: string; v: number; tags: string[] }
export function f90(x: M90): string { return x.id + x.v + x.tags.length }
