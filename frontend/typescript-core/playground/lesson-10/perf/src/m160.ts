export interface M160 { id: string; v: number; tags: string[] }
export function f160(x: M160): string { return x.id + x.v + x.tags.length }
