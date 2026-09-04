export interface M121 { id: string; v: number; tags: string[] }
export function f121(x: M121): string { return x.id + x.v + x.tags.length }
