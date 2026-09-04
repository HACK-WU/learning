export interface M132 { id: string; v: number; tags: string[] }
export function f132(x: M132): string { return x.id + x.v + x.tags.length }
