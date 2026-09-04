export interface M105 { id: string; v: number; tags: string[] }
export function f105(x: M105): string { return x.id + x.v + x.tags.length }
