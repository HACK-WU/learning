export interface M35 { id: string; v: number; tags: string[] }
export function f35(x: M35): string { return x.id + x.v + x.tags.length }
