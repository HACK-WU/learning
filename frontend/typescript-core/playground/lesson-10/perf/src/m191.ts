export interface M191 { id: string; v: number; tags: string[] }
export function f191(x: M191): string { return x.id + x.v + x.tags.length }
