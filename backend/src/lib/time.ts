/** Server-side clock helpers. Every timestamp used for reward/duration math
 * must come from here — never from a client-supplied field. */

export function nowSeconds(): number {
  return Math.floor(Date.now() / 1000);
}

export function uuid(): string {
  return crypto.randomUUID();
}

/** Clamp elapsed seconds between 0 and a cap (used for offline production). */
export function clampElapsed(elapsedSeconds: number, capSeconds: number): number {
  if (!Number.isFinite(elapsedSeconds) || elapsedSeconds < 0) return 0;
  return Math.min(elapsedSeconds, capSeconds);
}
