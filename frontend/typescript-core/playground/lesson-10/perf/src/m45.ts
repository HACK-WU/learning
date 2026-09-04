export interface M45 { id: string; v: number; tags: string[] }
export function f45(x: M45): string { return x.id + x.v + x.tags.length }
