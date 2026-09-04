export interface M28 { id: string; v: number; tags: string[] }
export function f28(x: M28): string { return x.id + x.v + x.tags.length }
