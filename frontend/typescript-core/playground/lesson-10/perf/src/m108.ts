export interface M108 { id: string; v: number; tags: string[] }
export function f108(x: M108): string { return x.id + x.v + x.tags.length }
