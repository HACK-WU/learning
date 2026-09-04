export interface M114 { id: string; v: number; tags: string[] }
export function f114(x: M114): string { return x.id + x.v + x.tags.length }
