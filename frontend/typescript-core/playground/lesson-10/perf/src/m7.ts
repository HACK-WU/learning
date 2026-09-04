export interface M7 { id: string; v: number; tags: string[] }
export function f7(x: M7): string { return x.id + x.v + x.tags.length }
