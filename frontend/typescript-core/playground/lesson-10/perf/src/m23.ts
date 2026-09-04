export interface M23 { id: string; v: number; tags: string[] }
export function f23(x: M23): string { return x.id + x.v + x.tags.length }
