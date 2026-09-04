export interface M41 { id: string; v: number; tags: string[] }
export function f41(x: M41): string { return x.id + x.v + x.tags.length }
