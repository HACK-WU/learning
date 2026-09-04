export interface M75 { id: string; v: number; tags: string[] }
export function f75(x: M75): string { return x.id + x.v + x.tags.length }
