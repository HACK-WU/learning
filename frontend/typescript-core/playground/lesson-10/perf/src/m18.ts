export interface M18 { id: string; v: number; tags: string[] }
export function f18(x: M18): string { return x.id + x.v + x.tags.length }
