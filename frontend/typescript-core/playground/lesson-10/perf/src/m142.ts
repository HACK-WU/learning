export interface M142 { id: string; v: number; tags: string[] }
export function f142(x: M142): string { return x.id + x.v + x.tags.length }
