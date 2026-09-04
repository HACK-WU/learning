export interface M91 { id: string; v: number; tags: string[] }
export function f91(x: M91): string { return x.id + x.v + x.tags.length }
