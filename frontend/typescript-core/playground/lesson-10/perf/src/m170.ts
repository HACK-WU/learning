export interface M170 { id: string; v: number; tags: string[] }
export function f170(x: M170): string { return x.id + x.v + x.tags.length }
