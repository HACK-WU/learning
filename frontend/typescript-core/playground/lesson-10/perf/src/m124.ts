export interface M124 { id: string; v: number; tags: string[] }
export function f124(x: M124): string { return x.id + x.v + x.tags.length }
