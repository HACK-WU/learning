export interface M63 { id: string; v: number; tags: string[] }
export function f63(x: M63): string { return x.id + x.v + x.tags.length }
