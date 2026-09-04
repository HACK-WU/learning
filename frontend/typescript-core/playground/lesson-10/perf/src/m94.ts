export interface M94 { id: string; v: number; tags: string[] }
export function f94(x: M94): string { return x.id + x.v + x.tags.length }
