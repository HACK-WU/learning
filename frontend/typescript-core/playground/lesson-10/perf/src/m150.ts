export interface M150 { id: string; v: number; tags: string[] }
export function f150(x: M150): string { return x.id + x.v + x.tags.length }
