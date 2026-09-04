export interface M86 { id: string; v: number; tags: string[] }
export function f86(x: M86): string { return x.id + x.v + x.tags.length }
