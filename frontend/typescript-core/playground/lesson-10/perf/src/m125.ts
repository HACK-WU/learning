export interface M125 { id: string; v: number; tags: string[] }
export function f125(x: M125): string { return x.id + x.v + x.tags.length }
