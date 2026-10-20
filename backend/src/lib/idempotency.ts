import type { Env, ResourceMap } from '../types';
import { newId } from './auth';
import { nowSeconds } from './time';

/**
 * Every resource-granting/spending endpoint funnels its D1 writes through
 * this helper. It guarantees that a given (player_id, idempotency_key) pair
 * is only ever applied once, which is what makes it safe for the iOS client
 * to retry a request after a dropped response (flaky cell connection,
 * background/foreground transition, etc.) without double-granting rewards.
 *
 * D1's `batch()` runs an array of statements atomically but does not
 * support branching on an intermediate read within that same atomic unit.
 * So the pattern here is:
 *   1. Fast-path SELECT: has this idempotency key already been recorded?
 *      If so, replay the stored response verbatim.
 *   2. Otherwise, run the caller's `compute()` (which itself reads current
 *      DB state and validates the action), then atomically batch its
 *      resulting write statements together with the INSERT into
 *      `transactions` that claims the idempotency key.
 *   3. If that batch fails on the UNIQUE(player_id, idempotency_key) index
 *      (a concurrent duplicate request won the race), re-select and return
 *      the winner's stored response instead of erroring.
 */
export interface IdempotentComputeResult<T> {
  /** D1 statements to run atomically (resource updates, inserts, etc). */
  statements: D1PreparedStatement[];
  /** Net resource deltas this action applied, stored for audit/debugging. */
  resourceDeltas: ResourceMap;
  /** The JSON-serializable response to return to the client (and replay). */
  response: T;
}

interface StoredTransactionRow {
  payload_json: string;
}

/**
 * Looks up a previously-recorded response for (player_id, idempotency_key),
 * if any. Route handlers MUST call this before running any validation that
 * reads current DB state (e.g. "is this grid cell free", "does the player
 * still have this contract accepted") and short-circuit on a hit. Otherwise
 * a genuine retry of an already-applied action — the exact case this
 * mechanism exists to make safe — would see its own already-applied side
 * effects (the module now occupying that cell, the contract now completed)
 * and fail validation instead of replaying the original success.
 */
export async function fetchStoredResponse<T>(
  env: Env,
  playerId: string,
  idempotencyKey: string
): Promise<T | undefined> {
  const row = await env.DB.prepare(
    `SELECT payload_json FROM transactions WHERE player_id = ? AND idempotency_key = ?`
  )
    .bind(playerId, idempotencyKey)
    .first<StoredTransactionRow>();

  if (!row) return undefined;
  const parsed = JSON.parse(row.payload_json) as { response: T };
  return parsed.response;
}

function isUniqueConstraintError(err: unknown): boolean {
  const message = err instanceof Error ? err.message : String(err);
  return message.toUpperCase().includes('UNIQUE CONSTRAINT');
}

export async function runIdempotent<T>(
  env: Env,
  playerId: string,
  idempotencyKey: string,
  kind: string,
  compute: () => Promise<IdempotentComputeResult<T>>
): Promise<T> {
  const existing = await fetchStoredResponse<T>(env, playerId, idempotencyKey);
  if (existing !== undefined) return existing;

  const { statements, resourceDeltas, response } = await compute();

  const txStatement = env.DB.prepare(
    `INSERT INTO transactions (id, player_id, idempotency_key, kind, resource_deltas_json, payload_json, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?)`
  ).bind(
    newId(),
    playerId,
    idempotencyKey,
    kind,
    JSON.stringify(resourceDeltas),
    JSON.stringify({ response }),
    nowSeconds()
  );

  try {
    await env.DB.batch([...statements, txStatement]);
  } catch (err) {
    if (isUniqueConstraintError(err)) {
      const winner = await fetchStoredResponse<T>(env, playerId, idempotencyKey);
      if (winner !== undefined) return winner;
    }
    throw err;
  }

  return response;
}

/**
 * Resolves the idempotency key for a request: prefers the `Idempotency-Key`
 * header (standard REST convention, easy for the client networking layer to
 * set uniformly), falls back to an `idempotencyKey` field in the JSON body,
 * and finally generates one server-side. A server-generated fallback still
 * gets logged in `transactions` but provides no replay protection for that
 * specific call — clients SHOULD always supply their own for any endpoint
 * that mutates resources, generated once per user-intent (e.g. once per
 * "Collect" button tap) and reused verbatim across retries of that same tap.
 */
export function resolveIdempotencyKey(request: Request, body: Record<string, unknown> | undefined): string {
  const header = request.headers.get('Idempotency-Key');
  if (header && header.trim().length > 0) return header.trim();
  const fromBody = body?.idempotencyKey;
  if (typeof fromBody === 'string' && fromBody.trim().length > 0) return fromBody.trim();
  return newId();
}
