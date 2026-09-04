export interface M199 { id: string; v: number; tags: string[] }
export function f199(x: M199): string { return x.id + x.v + x.tags.length }
