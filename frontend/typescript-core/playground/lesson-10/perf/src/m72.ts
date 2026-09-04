export interface M72 { id: string; v: number; tags: string[] }
export function f72(x: M72): string { return x.id + x.v + x.tags.length }
