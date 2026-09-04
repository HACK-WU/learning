export interface M110 { id: string; v: number; tags: string[] }
export function f110(x: M110): string { return x.id + x.v + x.tags.length }
