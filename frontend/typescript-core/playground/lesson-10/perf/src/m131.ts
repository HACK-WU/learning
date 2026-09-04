export interface M131 { id: string; v: number; tags: string[] }
export function f131(x: M131): string { return x.id + x.v + x.tags.length }
