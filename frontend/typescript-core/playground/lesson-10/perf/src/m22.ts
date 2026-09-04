export interface M22 { id: string; v: number; tags: string[] }
export function f22(x: M22): string { return x.id + x.v + x.tags.length }
