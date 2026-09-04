export interface M162 { id: string; v: number; tags: string[] }
export function f162(x: M162): string { return x.id + x.v + x.tags.length }
