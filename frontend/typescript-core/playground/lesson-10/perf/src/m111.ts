export interface M111 { id: string; v: number; tags: string[] }
export function f111(x: M111): string { return x.id + x.v + x.tags.length }
