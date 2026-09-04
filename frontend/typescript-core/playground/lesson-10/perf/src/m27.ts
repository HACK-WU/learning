export interface M27 { id: string; v: number; tags: string[] }
export function f27(x: M27): string { return x.id + x.v + x.tags.length }
