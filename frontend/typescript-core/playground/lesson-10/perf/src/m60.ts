export interface M60 { id: string; v: number; tags: string[] }
export function f60(x: M60): string { return x.id + x.v + x.tags.length }
