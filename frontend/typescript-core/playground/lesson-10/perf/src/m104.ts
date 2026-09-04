export interface M104 { id: string; v: number; tags: string[] }
export function f104(x: M104): string { return x.id + x.v + x.tags.length }
