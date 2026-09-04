export interface M10 { id: string; v: number; tags: string[] }
export function f10(x: M10): string { return x.id + x.v + x.tags.length }
