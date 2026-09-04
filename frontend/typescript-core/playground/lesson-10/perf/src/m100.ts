export interface M100 { id: string; v: number; tags: string[] }
export function f100(x: M100): string { return x.id + x.v + x.tags.length }
