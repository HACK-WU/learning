export interface M4 { id: string; v: number; tags: string[] }
export function f4(x: M4): string { return x.id + x.v + x.tags.length }
