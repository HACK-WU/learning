export interface M123 { id: string; v: number; tags: string[] }
export function f123(x: M123): string { return x.id + x.v + x.tags.length }
