// Flash messages travel in the URL so they survive the redirect after a form post.

export const FLASH_KEYS = { ok: "msg", error: "error" } as const;
export type FlashKind = keyof typeof FLASH_KEYS;

export function withFlash(path: string, kind: FlashKind, text: string): string {
  const url = new URL(path, "http://local");
  for (const key of Object.values(FLASH_KEYS)) url.searchParams.delete(key);
  url.searchParams.set(FLASH_KEYS[kind], text);
  return url.pathname + url.search;
}
