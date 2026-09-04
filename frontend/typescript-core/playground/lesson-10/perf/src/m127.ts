export interface M127 { id: string; v: number; tags: string[] }
export function f127(x: M127): string { return x.id + x.v + x.tags.length }
