export interface M135 { id: string; v: number; tags: string[] }
export function f135(x: M135): string { return x.id + x.v + x.tags.length }
