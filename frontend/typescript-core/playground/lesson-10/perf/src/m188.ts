export interface M188 { id: string; v: number; tags: string[] }
export function f188(x: M188): string { return x.id + x.v + x.tags.length }
