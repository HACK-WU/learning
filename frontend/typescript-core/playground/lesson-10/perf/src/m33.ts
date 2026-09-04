export interface M33 { id: string; v: number; tags: string[] }
export function f33(x: M33): string { return x.id + x.v + x.tags.length }
