export interface M129 { id: string; v: number; tags: string[] }
export function f129(x: M129): string { return x.id + x.v + x.tags.length }
