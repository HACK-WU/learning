export interface M38 { id: string; v: number; tags: string[] }
export function f38(x: M38): string { return x.id + x.v + x.tags.length }
