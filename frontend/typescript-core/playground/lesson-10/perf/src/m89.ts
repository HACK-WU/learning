export interface M89 { id: string; v: number; tags: string[] }
export function f89(x: M89): string { return x.id + x.v + x.tags.length }
