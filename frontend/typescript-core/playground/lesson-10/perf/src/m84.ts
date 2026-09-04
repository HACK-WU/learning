export interface M84 { id: string; v: number; tags: string[] }
export function f84(x: M84): string { return x.id + x.v + x.tags.length }
