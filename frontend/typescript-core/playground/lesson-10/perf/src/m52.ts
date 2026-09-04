export interface M52 { id: string; v: number; tags: string[] }
export function f52(x: M52): string { return x.id + x.v + x.tags.length }
