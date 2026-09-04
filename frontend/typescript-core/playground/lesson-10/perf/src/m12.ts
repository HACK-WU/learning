export interface M12 { id: string; v: number; tags: string[] }
export function f12(x: M12): string { return x.id + x.v + x.tags.length }
