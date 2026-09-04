export interface M117 { id: string; v: number; tags: string[] }
export function f117(x: M117): string { return x.id + x.v + x.tags.length }
