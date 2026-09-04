export interface M78 { id: string; v: number; tags: string[] }
export function f78(x: M78): string { return x.id + x.v + x.tags.length }
