export interface M76 { id: string; v: number; tags: string[] }
export function f76(x: M76): string { return x.id + x.v + x.tags.length }
