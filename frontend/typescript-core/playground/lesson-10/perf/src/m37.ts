export interface M37 { id: string; v: number; tags: string[] }
export function f37(x: M37): string { return x.id + x.v + x.tags.length }
