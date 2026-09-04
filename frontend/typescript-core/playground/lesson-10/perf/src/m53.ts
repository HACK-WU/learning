export interface M53 { id: string; v: number; tags: string[] }
export function f53(x: M53): string { return x.id + x.v + x.tags.length }
