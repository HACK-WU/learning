export interface M163 { id: string; v: number; tags: string[] }
export function f163(x: M163): string { return x.id + x.v + x.tags.length }
