export interface M164 { id: string; v: number; tags: string[] }
export function f164(x: M164): string { return x.id + x.v + x.tags.length }
