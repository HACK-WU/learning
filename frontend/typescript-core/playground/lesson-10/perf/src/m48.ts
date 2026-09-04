export interface M48 { id: string; v: number; tags: string[] }
export function f48(x: M48): string { return x.id + x.v + x.tags.length }
