export interface M69 { id: string; v: number; tags: string[] }
export function f69(x: M69): string { return x.id + x.v + x.tags.length }
